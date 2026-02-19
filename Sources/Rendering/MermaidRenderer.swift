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
    @Published var lastExportError: String?
    let webView: DiagramWebView
    let validator: DiagramRuntimeValidator
    internal var lastSource: String = ""
    private var renderTask: Task<Void, Never>?
    private let debounceInterval: Duration = .milliseconds(300)
    internal let logger = Logging.logger(category: "mermaid")
    internal var mermaidReady = false
    private var pendingSource: String?
    internal let zoomStep: Double = 0.1
    internal let minZoom: Double = 0.25
    internal let maxZoom: Double = 5.0

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

        contentController.add(
            ScriptMessageHandler(renderer: self, name: "ready") { renderer, _ in
                renderer.handleMermaidReady()
            },
            name: "ready"
        )
        contentController.add(
            ScriptMessageHandler(renderer: self, name: "zoomChanged") { renderer, body in
                renderer.handleZoomChangedMessage(body)
            },
            name: "zoomChanged"
        )
        webView.navigationDelegate = self
        loadBaseHTML()
        
        webView.copyPNGHandler = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let exporter = DiagramExporter(webView: self.webView)
                let result = await exporter.copyAsPNG()
                switch result {
                case .success(let pngData):
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setData(pngData, forType: .png)
                    self.lastExportError = nil
                case .failure(let error):
                    self.lastExportError = error.errorDescription
                }
            }
        }

        webView.copySVGHandler = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let exporter = DiagramExporter(webView: self.webView)
                let result = await exporter.copySVG()
                switch result {
                case .success(let svg):
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(svg, forType: .string)
                    self.lastExportError = nil
                case .failure(let error):
                    self.lastExportError = error.errorDescription
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
                
                if let metrics = await validator.fetchMetrics() {
                    guard metrics.hasSVG else {
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

            await validator.auditDOM(context: "post-render")
        } catch {
            if !Task.isCancelled {
                logger.error("Render failed: \(error.localizedDescription)")
                state = .failure(message: error.localizedDescription)
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
            state = .failure(message: "Missing preview renderer resource")
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
        state = .failure(message: message)
    }
}
