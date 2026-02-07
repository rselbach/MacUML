import Foundation
import WebKit
import Combine
import os
import AppKit

class DiagramWebView: WKWebView {
    var copyPNGHandler: (() -> Void)?
    var copySVGHandler: (() -> Void)?
    
    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        menu.removeAllItems()
        
        let pngItem = NSMenuItem(title: "Copy as PNG", action: #selector(handleCopyPNG), keyEquivalent: "")
        pngItem.target = self
        menu.addItem(pngItem)
        
        let svgItem = NSMenuItem(title: "Copy as SVG", action: #selector(handleCopySVG), keyEquivalent: "")
        svgItem.target = self
        menu.addItem(svgItem)
        
        super.willOpenMenu(menu, with: event)
    }
    
    @objc private func handleCopyPNG() {
        copyPNGHandler?()
    }
    
    @objc private func handleCopySVG() {
        copySVGHandler?()
    }
}

enum MermaidRenderState: Equatable {
    case idle
    case rendering
    case ready
    case failure(String)
}

struct MermaidError: Equatable {
    let message: String
    let line: Int?
}

enum MermaidTheme: String, CaseIterable {
    case auto = "auto"
    case `default` = "default"
    case dark = "dark"
    case forest = "forest"
    case neutral = "neutral"
    case base = "base"
    
    var label: String {
        switch self {
        case .auto: return "Auto"
        case .default: return "Default"
        case .dark: return "Dark"
        case .forest: return "Forest"
        case .neutral: return "Neutral"
        case .base: return "Base"
        }
    }
}



@MainActor
class MermaidRenderer: NSObject, ObservableObject {
    @Published private(set) var state: MermaidRenderState = .idle
    @Published private(set) var currentError: MermaidError?
    @Published private(set) var zoomLevel: Double = 1.0
    @Published var theme: MermaidTheme = .auto {
        didSet {
            if oldValue != theme {
                applyTheme()
            }
        }
    }
    let webView: DiagramWebView
    private var lastSource: String = ""
    private var renderTask: Task<Void, Never>?
    private var previewRuntimeValidationTask: Task<Void, Never>?
    private var trustedPreviewFiles: Set<URL> = []
    private let debounceInterval: Duration = .milliseconds(300)
    private let logger = Logger(subsystem: "com.macuml", category: "mermaid")
    private var mermaidReady = false
    private var pendingSource: String?
    private let zoomStep: Double = 0.1
    private let minZoom: Double = 0.25
    private let maxZoom: Double = 5.0

    nonisolated static func normalizedFileURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    nonisolated static func navigationPolicy(for requestURL: URL?, trustedLocalFiles: Set<URL>) -> WKNavigationActionPolicy {
        guard let requestURL else {
            return .cancel
        }

        if requestURL.scheme == "about" {
            return .allow
        }

        guard requestURL.isFileURL else {
            return .cancel
        }

        let normalizedRequestURL = normalizedFileURL(requestURL)
        return trustedLocalFiles.contains(normalizedRequestURL) ? .allow : .cancel
    }

    nonisolated static func navigationPolicy(for requestURL: URL?) -> WKNavigationActionPolicy {
        navigationPolicy(for: requestURL, trustedLocalFiles: [])
    }

    override init() {
        let config = WKWebViewConfiguration()

        let contentController = WKUserContentController()
        config.userContentController = contentController

        webView = DiagramWebView(frame: .zero, configuration: config)
#if DEBUG
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }
#endif
        webView.setValue(false, forKey: "drawsBackground")

        super.init()
        
        if let savedTheme = MermaidTheme(rawValue: AppSettings.shared.defaultDiagramTheme) {
            theme = savedTheme
        }

        contentController.add(ReadyHandler(renderer: self), name: "ready")
        contentController.add(ZoomChangedHandler(renderer: self), name: "zoomChanged")
        webView.navigationDelegate = self
        loadBaseHTML()
        
        webView.copyPNGHandler = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                guard let pngData = await self.copyAsPNG() else { return }
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setData(pngData, forType: .png)
            }
        }
        
        webView.copySVGHandler = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                guard let svg = await self.copySVG() else { return }
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(svg, forType: .string)
            }
        }
        
        logger.info("MermaidRenderer init complete")
    }

    func render(source: String, force: Bool = false) {
        guard force || source != lastSource else { return }
        lastSource = source

        renderTask?.cancel()
        currentError = nil
        
        guard mermaidReady else {
            logger.info("Mermaid not ready, queueing render")
            pendingSource = source
            schedulePreviewRuntimeValidation()
            return
        }

        renderTask = Task {
            do {
                try await Task.sleep(for: debounceInterval)
            } catch {
                return
            }

            await performRender(source: source)
        }
    }

    func zoomIn() {
        setZoom(zoomLevel + zoomStep)
    }

    func zoomOut() {
        setZoom(zoomLevel - zoomStep)
    }

    func resetZoom() {
        setZoom(1.0)
    }

    private func setZoom(_ newLevel: Double) {
        let rounded = (clampZoom(newLevel) * 100).rounded() / 100
        zoomLevel = rounded

        guard mermaidReady else { return }
        Task {
            await applyZoom(level: rounded)
        }
    }

    private func clampZoom(_ level: Double) -> Double {
        min(max(level, minZoom), maxZoom)
    }

    private func applyZoom(level: Double) async {
        let js = "window.setZoom(\(level));"
        do {
            let result = try await webView.evaluateJavaScript(js)
            if let zoom = result as? Double {
                zoomLevel = zoom
                return
            }

            if let zoom = result as? NSNumber {
                zoomLevel = zoom.doubleValue
            }
        } catch {
            logger.error("Failed to set zoom to \(level, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func performRender(source: String) async {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            state = .idle
            clearDiagram()
            return
        }

        state = .rendering

        let js = """
            if (typeof window.renderDiagram !== 'function') {
                return { success: false, error: 'renderDiagram not defined' };
            }
            return await window.renderDiagram(source);
            """

        do {
            let result = try await webView.callAsyncJavaScript(
                js,
                arguments: ["source": trimmed],
                contentWorld: .page
            )
            
            guard !Task.isCancelled else { return }
            
            if let dict = result as? [String: Any],
               let success = dict["success"] as? Bool {
                if success {
                    if let stale = dict["stale"] as? Bool, stale {
                        logger.debug("Dropping stale render result")
                        return
                    }
                    if let metrics = await fetchDiagramMetrics() {
                        if !metrics.hasSVG {
                            let message = "Render reported success, but no SVG was found in preview."
                            logger.error("\(message, privacy: .public)")
                            state = .failure(message)
                            currentError = MermaidError(message: message, line: nil)
                            return
                        }
                        let viewHasSize = webView.bounds.width > 1 && webView.bounds.height > 1
                        if viewHasSize && (metrics.width <= 1 || metrics.height <= 1) {
                            let message = "Rendered SVG has invalid size (\(metrics.width)x\(metrics.height))."
                            logger.error("\(message, privacy: .public)")
                            state = .failure(message)
                            currentError = MermaidError(message: message, line: nil)
                            return
                        }
                    }
                    logger.info("Render succeeded")
                    state = .ready
                    currentError = nil
                } else if let error = dict["error"] as? String {
                    logger.info("Render failed: \(error)")
                    let line = dict["line"] as? Int
                    state = .failure(error)
                    currentError = MermaidError(message: error, line: line)
                } else {
                    let fallbackError = "Failed to render diagram"
                    logger.error("\(fallbackError, privacy: .public)")
                    state = .failure(fallbackError)
                    currentError = MermaidError(message: fallbackError, line: nil)
                }
            } else {
                state = .ready
            }

            await auditPreviewDOM(context: "post-render")
        } catch {
            if !Task.isCancelled {
                logger.error("Render failed: \(error.localizedDescription)")
                state = .failure(error.localizedDescription)
                await auditPreviewDOM(context: "render-error")
            }
        }
    }

    private func clearDiagram() {
        let js = "document.getElementById('diagram').innerHTML = '';"
        webView.evaluateJavaScript(js)
    }

    private func applyTheme() {
        let js = "window.setTheme('\(theme.rawValue)');"
        webView.evaluateJavaScript(js) { [weak self] _, _ in
            guard let self, !self.lastSource.isEmpty else { return }
            Task { @MainActor in
                await self.performRender(source: self.lastSource)
            }
        }
    }

    private func loadBaseHTML() {
        let previewCandidates = [
            Bundle.main.url(forResource: "preview", withExtension: "html"),
            Bundle.module.url(forResource: "preview", withExtension: "html")
        ].compactMap { $0 }

        guard let previewURL = previewCandidates.first else {
            logger.error("Failed to find bundled preview.html")
            state = .failure("Missing preview renderer resource")
            return
        }

        trustedPreviewFiles = Set(previewCandidates.map(Self.normalizedFileURL))
        let normalizedPreviewURL = Self.normalizedFileURL(previewURL)
        webView.loadFileURL(normalizedPreviewURL, allowingReadAccessTo: normalizedPreviewURL.deletingLastPathComponent())
    }

    private func schedulePreviewRuntimeValidation() {
        guard previewRuntimeValidationTask == nil else {
            return
        }

        previewRuntimeValidationTask = Task { @MainActor in
            await validatePreviewRuntime()
            previewRuntimeValidationTask = nil
        }
    }

    private func validatePreviewRuntime() async {
        let hasSource = !lastSource.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let js = """
            (function() {
                return {
                    hasMermaid: typeof mermaid !== 'undefined',
                    hasRenderDiagram: typeof window.renderDiagram === 'function',
                    hasSetTheme: typeof window.setTheme === 'function',
                    hasSetZoom: typeof window.setZoom === 'function'
                };
            })()
            """

        var lastFlags: (Bool, Bool, Bool, Bool)?
        for _ in 0..<20 {
            do {
                guard let result = try await webView.evaluateJavaScript(js) as? [String: Any] else {
                    try await Task.sleep(for: .milliseconds(100))
                    continue
                }

                let hasMermaid = result["hasMermaid"] as? Bool ?? false
                let hasRenderDiagram = result["hasRenderDiagram"] as? Bool ?? false
                let hasSetTheme = result["hasSetTheme"] as? Bool ?? false
                let hasSetZoom = result["hasSetZoom"] as? Bool ?? false
                lastFlags = (hasMermaid, hasRenderDiagram, hasSetTheme, hasSetZoom)

                if hasMermaid && hasRenderDiagram && hasSetTheme && hasSetZoom {
                    if !mermaidReady {
                        logger.info("Preview runtime validated before ready callback; enabling fallback readiness")
                        handleMermaidReady()
                    }
                    return
                }
            } catch {
                logger.error("Preview runtime validation attempt failed: \(error.localizedDescription, privacy: .public)")
            }

            do {
                try await Task.sleep(for: .milliseconds(100))
            } catch {
                return
            }
        }

        if let lastFlags {
            logger.error(
                "Preview runtime invalid: hasMermaid=\(lastFlags.0, privacy: .public), hasRenderDiagram=\(lastFlags.1, privacy: .public), hasSetTheme=\(lastFlags.2, privacy: .public), hasSetZoom=\(lastFlags.3, privacy: .public)"
            )
            if hasSource {
                state = .failure("Preview runtime failed (mermaid:\(lastFlags.0), render:\(lastFlags.1), theme:\(lastFlags.2), zoom:\(lastFlags.3))")
            }
            return
        }

        logger.error("Preview runtime validation returned no usable result")
        if hasSource {
            state = .failure("Preview runtime did not initialize")
        }
    }

    private func auditPreviewDOM(context: String) async {
        let js = """
            if (typeof window.collectPreviewDiagnostics !== 'function') {
                return null;
            }
            return window.collectPreviewDiagnostics();
            """

        do {
            guard let result = try await webView.evaluateJavaScript(js) as? [String: Any],
                  let extraNodeCount = result["extraNodeCount"] as? Int,
                  extraNodeCount > 0 else {
                return
            }

            var details = "[]"
            if let extras = result["extras"] as? [[String: Any]],
               let data = try? JSONSerialization.data(withJSONObject: extras, options: []),
               let text = String(data: data, encoding: .utf8) {
                details = text
            }

            logger.error(
                "Preview DOM audit (\(context, privacy: .public)): extra nodes=\(extraNodeCount, privacy: .public), details=\(details, privacy: .public)"
            )
        } catch {
            logger.error("Preview DOM audit failed (\(context, privacy: .public)): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func fetchDiagramMetrics() async -> (hasSVG: Bool, width: Double, height: Double)? {
        let js = """
            (function() {
                const svg = document.querySelector('#diagram svg');
                if (!svg) {
                    return { hasSVG: false, width: 0, height: 0 };
                }
                const rect = svg.getBoundingClientRect();
                return { hasSVG: true, width: rect.width, height: rect.height };
            })()
            """

        do {
            guard let result = try await webView.evaluateJavaScript(js) as? [String: Any],
                  let hasSVG = result["hasSVG"] as? Bool,
                  let width = result["width"] as? Double,
                  let height = result["height"] as? Double else {
                return nil
            }
            return (hasSVG, width, height)
        } catch {
            logger.error("Failed to fetch diagram metrics: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func copyAsPNG() async -> Data? {
        let config = WKSnapshotConfiguration()
        config.afterScreenUpdates = true

        if let rect = await getDiagramBounds() {
            let padding: CGFloat = 16
            let paddedRect = CGRect(
                x: max(0, rect.origin.x - padding),
                y: max(0, rect.origin.y - padding),
                width: rect.width + padding * 2,
                height: rect.height + padding * 2
            )
            let viewBounds = webView.bounds
            config.rect = paddedRect.intersection(viewBounds)
        }

        do {
            let image = try await webView.takeSnapshot(configuration: config)
            guard let tiffData = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData),
                  let pngData = bitmap.representation(using: .png, properties: [:]) else {
                return nil
            }
            return pngData
        } catch {
            logger.error("Snapshot failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func getDiagramBounds() async -> CGRect? {
        let js = """
            (function() {
                const svg = document.querySelector('#diagram svg');
                if (!svg) return null;
                const rect = svg.getBoundingClientRect();
                return { x: rect.x, y: rect.y, width: rect.width, height: rect.height };
            })()
            """
        do {
            guard let result = try await webView.evaluateJavaScript(js) as? [String: Any],
                  let x = result["x"] as? Double,
                  let y = result["y"] as? Double,
                  let width = result["width"] as? Double,
                  let height = result["height"] as? Double else {
                return nil
            }
            return CGRect(x: x, y: y, width: width, height: height)
        } catch {
            logger.error("Failed to get diagram bounds: \(error.localizedDescription)")
            return nil
        }
    }

    func copySVG() async -> String? {
        let js = """
            (function() {
                const svg = document.querySelector('#diagram svg');
                return svg ? svg.outerHTML : '';
            })()
            """
        do {
            let result = try await webView.evaluateJavaScript(js)
            return result as? String
        } catch {
            logger.error("SVG extraction failed: \(error.localizedDescription)")
            return nil
        }
    }
    func handleMermaidReady() {
        guard !mermaidReady else { return }
        mermaidReady = true
        applyTheme()
        Task {
            await applyZoom(level: zoomLevel)
        }
        if let source = pendingSource {
            pendingSource = nil
            render(source: source, force: true)
        }
    }

    func handleZoomChangedMessage(_ body: Any) {
        let rawLevel: Double

        if let value = body as? NSNumber {
            rawLevel = value.doubleValue
        } else if let value = body as? Double {
            rawLevel = value
        } else if let value = body as? String, let parsed = Double(value) {
            rawLevel = parsed
        } else {
            logger.error("zoomChanged bridge payload is invalid: \(String(describing: body), privacy: .public)")
            return
        }

        let normalized = (clampZoom(rawLevel) * 100).rounded() / 100
        guard abs(normalized - zoomLevel) >= 0.0001 else {
            return
        }

        zoomLevel = normalized
    }
}

private class ReadyHandler: NSObject, WKScriptMessageHandler {
    weak var renderer: MermaidRenderer?
    init(renderer: MermaidRenderer) { self.renderer = renderer }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        Task { @MainActor in
            renderer?.handleMermaidReady()
        }
    }
}

private class ZoomChangedHandler: NSObject, WKScriptMessageHandler {
    weak var renderer: MermaidRenderer?

    init(renderer: MermaidRenderer) {
        self.renderer = renderer
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        Task { @MainActor in
            renderer?.handleZoomChangedMessage(message.body)
        }
    }
}

extension MermaidRenderer: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        decisionHandler(Self.navigationPolicy(for: navigationAction.request.url, trustedLocalFiles: trustedPreviewFiles))
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            schedulePreviewRuntimeValidation()
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            logger.error("Navigation failed: \(error.localizedDescription)")
            state = .failure("Failed to load renderer")
        }
    }
}
