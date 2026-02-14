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
    internal var lastSource: String = ""
    private var renderTask: Task<Void, Never>?
    internal var previewRuntimeValidationTask: Task<Void, Never>?
    internal var trustedPreviewFiles: Set<URL> = []
    private let debounceInterval: Duration = .milliseconds(300)
    internal let logger = Logger(subsystem: "com.macuml", category: "mermaid")
    internal var mermaidReady = false
    private var pendingSource: String?
    internal let zoomStep: Double = 0.1
    internal let minZoom: Double = 0.25
    internal let maxZoom: Double = 5.0
    internal let validationMaxAttempts: Int = 20
    internal let validationInitialDelay: Duration = .milliseconds(50)
    internal let validationMaxDelay: Duration = .milliseconds(500)

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

        super.init()
        
        theme = AppSettings.shared.defaultDiagramTheme

        contentController.add(ReadyHandler(renderer: self), name: "ready")
        contentController.add(ZoomChangedHandler(renderer: self), name: "zoomChanged")
        webView.navigationDelegate = self
        webView.uiDelegate = self
        loadBaseHTML()
        
        webView.copyPNGHandler = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                let exporter = DiagramExporter(webView: self.webView)
                guard let pngData = await exporter.copyAsPNG() else { return }
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setData(pngData, forType: .png)
            }
        }

        webView.copySVGHandler = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                let exporter = DiagramExporter(webView: self.webView)
                guard let svg = await exporter.copySVG() else { return }
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(svg, forType: .string)
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
                            state = .failure(message: message)
                            return
                        }
                        let viewHasSize = webView.bounds.width > 1 && webView.bounds.height > 1
                        if viewHasSize && (metrics.width <= 1 || metrics.height <= 1) {
                            let message = "Rendered SVG has invalid size (\(metrics.width)x\(metrics.height))."
                            logger.error("\(message, privacy: .public)")
                            state = .failure(message: message)
                            return
                        }
                    }
                    logger.info("Render succeeded")
                    state = .ready
                } else if let error = dict["error"] as? String {
                    logger.info("Render failed: \(error)")
                    let line = dict["line"] as? Int
                    state = .failure(message: error, line: line)
                } else {
                    let fallbackError = "Failed to render diagram"
                    logger.error("\(fallbackError, privacy: .public)")
                    state = .failure(message: fallbackError)
                }
            } else {
                state = .ready
            }

            await auditPreviewDOM(context: "post-render")
        } catch {
            if !Task.isCancelled {
                logger.error("Render failed: \(error.localizedDescription)")
                state = .failure(message: error.localizedDescription)
                await auditPreviewDOM(context: "render-error")
            }
        }
    }

    private func clearDiagram() async throws {
        try await webView.evaluateJavaScript("document.getElementById('diagram').innerHTML = '';")
    }

    private func loadBaseHTML() {
        // Bundle.module uses a SwiftPM-generated accessor that calls fatalError
        // when the resource bundle isn't found. In released .app bundles the
        // resource bundle doesn't exist (resources are copied loose into
        // Contents/Resources/ by bundle-app.sh), so we must avoid accessing
        // Bundle.module when Bundle.main already has the file.  The ??
        // operator's @autoclosure right-hand side gives us exactly that:
        // Bundle.module is never evaluated when Bundle.main succeeds.
        let previewURL = Bundle.main.url(forResource: "preview", withExtension: "html")
            ?? Bundle.module.url(forResource: "preview", withExtension: "html")

        guard let previewURL else {
            logger.error("Failed to find bundled preview.html")
            state = .failure(message: "Missing preview renderer resource")
            return
        }

        let normalizedPreviewURL = DiagramSecurityPolicy.normalizedFileURL(previewURL)
        trustedPreviewFiles = [normalizedPreviewURL]
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
}
