import Foundation
import WebKit
import os
import AppKit

/// Renders Mermaid diagrams in a WebView.
///
/// Manages the lifecycle of a WebView that renders Mermaid.js diagrams with:
/// - Debounced rendering to avoid excessive re-renders during typing
/// - Theme switching (auto, default, dark, forest, neutral, base)
/// - Zoom controls with keyboard shortcuts
/// - Error propagation with optional line information
/// - Export to PNG/SVG via clipboard
///
/// Usage:
/// ```swift
/// let renderer = MermaidRenderer()
/// renderer.render(source: "flowchart TD\nA-->B")
/// ```
@MainActor
class MermaidRenderer: NSObject, ObservableObject {
    @Published var state: MermaidRenderState = .idle
    @Published var zoomLevel: Double = 1.0
    @Published var theme: MermaidTheme = .auto {
        didSet {
            if oldValue != theme {
                applyTheme()
            }
        }
    }
    let webView: DiagramWebView
    let validator: DiagramRuntimeValidator
    internal var lastSource: String = ""
    private var renderTask: Task<Void, Never>?
    private let debounceInterval: Duration = .milliseconds(300)
    internal let logger = Logging.logger(category: "mermaid")
    internal var mermaidReady = false
    private var pendingSource: String?
    internal static let zoomStep: Double = 0.1
    internal static let minZoom: Double = 0.25
    internal static let maxZoom: Double = 5.0

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let contentController = WKUserContentController()
        config.userContentController = contentController

        webView = DiagramWebView(frame: .zero, configuration: config)
#if DEBUG
        webView.isInspectable = true
#endif
        webView.underPageBackgroundColor = .clear

        validator = DiagramRuntimeValidator(webView: webView)

        super.init()

        validator.configure(
            hasSource: { [weak self] in self?.hasSourceContent() ?? false },
            onReady: { [weak self] in self?.handleValidatorReady() },
            onFailure: { [weak self] message in self?.handleValidatorFailure(message: message) }
        )
        
        theme = AppSettings.shared.defaultDiagramTheme

        contentController.add(self, name: "ready")
        contentController.add(self, name: "zoomChanged")
        webView.navigationDelegate = self
        loadBaseHTML()
        
        webView.copyPNGHandler = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if case .success(let pngData) = await DiagramExporter(webView: self.webView).copyAsPNG() {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setData(pngData, forType: .png)
                }
            }
        }

        webView.copySVGHandler = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if case .success(let svg) = await DiagramExporter(webView: self.webView).copySVG() {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(svg, forType: .string)
                }
            }
        }
        
        logger.info("MermaidRenderer init complete")
    }

    func refreshCurrentSource() {
        render(source: lastSource, force: true)
    }

    func render(source: String, force: Bool = false) {
        guard force || source != lastSource else { return }
        lastSource = source

        renderTask?.cancel()
        
        guard mermaidReady else {
            logger.info("Mermaid not ready, queueing render")
            pendingSource = source
            validator.scheduleValidation()
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

    internal func performRender(source: String) async {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            state = .idle
            do {
                try await clearDiagram()
            } catch {
                logger.error("Failed to clear diagram: \(error.localizedDescription, privacy: .public)")
            }
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
            
            guard let dict = result as? [String: Any], let success = dict["success"] as? Bool else {
                state = .ready
                await validator.auditDOM(context: "post-render")
                return
            }

            if success {
                if dict["stale"] as? Bool == true {
                    logger.debug("Dropping stale render result")
                    return
                }
                
                if var metrics = await validator.fetchMetrics() {
                    guard metrics.hasSVG else {
                        let message = "Render reported success, but no SVG was found in preview."
                        logger.error("\(message, privacy: .public)")
                        state = .failure(error: MermaidError(message: message, line: nil))
                        return
                    }

                    let viewHasSize = webView.bounds.width > 1 && webView.bounds.height > 1
                    if viewHasSize && (metrics.width <= 1 || metrics.height <= 1) {
                        // Layout may not have settled yet; retry once after a
                        // brief delay before treating this as a real error.
                        try? await Task.sleep(for: .milliseconds(100))
                        guard !Task.isCancelled else { return }
                        if let retry = await validator.fetchMetrics(),
                           retry.hasSVG {
                            metrics = retry
                        }
                    }

                    if viewHasSize && (metrics.width <= 1 || metrics.height <= 1) {
                        let message = "Rendered SVG has invalid size (\(metrics.width)x\(metrics.height))."
                        logger.error("\(message, privacy: .public)")
                        state = .failure(error: MermaidError(message: message, line: nil))
                        return
                    }
                }
                
                logger.info("Render succeeded")
                state = .ready
            } else if let error = dict["error"] as? String {
                logger.info("Render failed: \(error)")
                let line = dict["line"] as? Int
                state = .failure(error: MermaidError(message: error, line: line))
            } else {
                let fallbackError = "Failed to render diagram"
                logger.error("\(fallbackError, privacy: .public)")
                state = .failure(error: MermaidError(message: fallbackError, line: nil))
            }

            await validator.auditDOM(context: "post-render")
        } catch {
            if !Task.isCancelled {
                logger.error("Render failed: \(error.localizedDescription)")
                state = .failure(error: MermaidError(message: error.localizedDescription, line: nil))
                await validator.auditDOM(context: "render-error")
            }
        }
    }

    private func clearDiagram() async throws {
        try await webView.evaluateJavaScript("document.getElementById('diagram').innerHTML = '';")
    }

    private func loadBaseHTML() {
        guard let previewURL = Bundle.appResource(name: "preview", extension: "html") else {
            logger.error("Failed to find bundled preview.html")
            state = .failure(error: MermaidError(message: "Missing preview renderer resource", line: nil))
            return
        }

        let normalizedPreviewURL = DiagramSecurityPolicy.normalizedFileURL(previewURL)
        validator.trustedPreviewFiles = [normalizedPreviewURL]
        webView.loadFileURL(normalizedPreviewURL, allowingReadAccessTo: normalizedPreviewURL.deletingLastPathComponent())
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

    private func hasSourceContent() -> Bool {
        !lastSource.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func handleValidatorReady() {
        if !mermaidReady {
            logger.info("Validator detected readiness before callback; enabling fallback")
            handleMermaidReady()
        }
    }

    private func handleValidatorFailure(message: String) {
        state = .failure(error: MermaidError(message: message, line: nil))
    }
}

extension MermaidRenderer: WKScriptMessageHandler {
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame else { return }
        switch message.name {
        case "ready":
            handleMermaidReady()
        case "zoomChanged":
            handleZoomChangedMessage(message.body)
        default:
            break
        }
    }
}

extension MermaidRenderer: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        decisionHandler(DiagramSecurityPolicy.navigationPolicy(
            for: navigationAction.request.url,
            trustedLocalFiles: validator.trustedPreviewFiles
        ))
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            validator.scheduleValidation()
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            logger.error("Navigation failed: \(error.localizedDescription)")
            state = .failure(error: MermaidError(message: "Failed to load renderer", line: nil))
        }
    }
}

extension MermaidRenderer {
    internal func applyTheme() {
        guard mermaidReady else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                _ = try await webView.callAsyncJavaScript(
                    "window.setTheme(themeName);",
                    arguments: ["themeName": self.theme.rawValue],
                    contentWorld: .page
                )
            } catch {
                self.logger.error("Failed to apply preview theme '\(self.theme.rawValue, privacy: .public)': \(error.localizedDescription, privacy: .public)")
                self.state = .failure(error: MermaidError(message: "Failed to apply theme '\(self.theme.rawValue)': \(error.localizedDescription)", line: nil))
            }
        }
    }
}

extension MermaidRenderer {
    private static let zoomEpsilon: Double = 0.0001

    func zoomIn() {
        setZoom(zoomLevel + Self.zoomStep)
    }

    func zoomOut() {
        setZoom(zoomLevel - Self.zoomStep)
    }

    func resetZoom() {
        setZoom(1.0)
    }

    internal func setZoom(_ newLevel: Double) {
        let rounded = (clampZoom(newLevel) * 100).rounded() / 100
        zoomLevel = rounded

        guard mermaidReady else { return }
        Task {
            await applyZoom(level: rounded)
        }
    }

    internal func clampZoom(_ level: Double) -> Double {
        min(max(level, Self.minZoom), Self.maxZoom)
    }

    internal func applyZoom(level: Double) async {
        do {
            _ = try await webView.callAsyncJavaScript(
                "window.setZoom(level);",
                arguments: ["level": level],
                contentWorld: .page
            )
        } catch {
            logger.error("Failed to set zoom to \(level, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    func handleZoomChangedMessage(_ body: Any) {
        guard let rawLevel = coerceToDouble(body) else {
            logger.error("zoomChanged bridge payload is invalid: \(String(describing: body), privacy: .public)")
            return
        }

        let normalized = (clampZoom(rawLevel) * 100).rounded() / 100
        guard abs(normalized - zoomLevel) >= Self.zoomEpsilon else {
            return
        }

        zoomLevel = normalized
    }

    private func coerceToDouble(_ value: Any) -> Double? {
        (value as? NSNumber)?.doubleValue ?? value as? Double ?? Double(value as? String ?? "")
    }
}
