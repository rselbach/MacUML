import AppKit
import Foundation
import WebKit
import os

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
    private nonisolated static let scriptMessageNames = ["ready", "zoomChanged", "appearanceChanged"]

    @Published var state: MermaidRenderState = .idle
    @Published var zoomLevel: Double = 1.0
    @Published private(set) var hasDiagram = false
    @Published private(set) var isPreviewStale = false
    @Published private(set) var canExport = false
    @Published var isLivePreviewEnabled = true {
        didSet {
            guard oldValue != isLivePreviewEnabled else { return }
            if isLivePreviewEnabled {
                refreshCurrentSource()
            } else {
                renderTask?.cancel()
                state = hasDiagram ? .ready : .idle
            }
        }
    }
    @Published var theme: MermaidTheme = .auto {
        didSet {
            if oldValue != theme {
                applyTheme()
            }
        }
    }
    var exportErrorHandler: ((ExportError) -> Void)?
    let webView: DiagramWebView
    let validator: DiagramRuntimeValidator
    private let contentController: WKUserContentController
    internal var lastSource: String = ""
    private var renderTask: Task<Void, Never>?
    private var renderRevision: UInt64 = 0
    private var successfulRevision: UInt64?
    private let debounceInterval: Duration = .milliseconds(300)
    internal let logger = Logging.logger(category: "mermaid")
    internal var mermaidReady = false
    private var recoveryAttempts = 0
    private let maximumRecoveryAttempts = 2
    internal static let zoomStep: Double = 0.1
    internal static let minZoom: Double = 0.25
    internal static let maxZoom: Double = 5.0

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        contentController = WKUserContentController()
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

        for name in Self.scriptMessageNames {
            contentController.add(WeakScriptMessageHandler(delegate: self), name: name)
        }
        webView.navigationDelegate = self
        loadBaseHTML()

        webView.canCopyHandler = { [weak self] in
            self?.canExport ?? false
        }

        webView.copyPNGHandler = { [weak self] in self?.copyFromContextMenu(.png) }
        webView.copySVGHandler = { [weak self] in self?.copyFromContextMenu(.svg) }

        logger.info("MermaidRenderer init complete")
    }

    deinit {
        let contentController = contentController
        Task { @MainActor in
            for name in Self.scriptMessageNames {
                contentController.removeScriptMessageHandler(forName: name)
            }
        }
    }

    func export(
        _ format: DiagramExportFormat, background: ExportBackground = AppSettings.shared.exportBackground
    ) async throws(ExportError) -> Data {
        guard canExport else { throw .noDiagram }
        let revision = renderRevision
        let exporter = DiagramExporter(webView: webView)
        let data: Data
        switch format {
        case .png:
            data = try await exporter.copyAsPNG(background: background).get()
        case .svg:
            data = try await exporter.copySVG(background: background).map { Data($0.utf8) }.get()
        }
        guard revision == renderRevision, canExport else { throw .previewChanged }
        return data
    }

    func copyDiagram(_ format: DiagramExportFormat) async throws(ExportError) {
        let data = try await export(format)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setData(data, forType: format.pasteboardType) else {
            throw .pasteboardWriteFailed
        }
        if format == .svg,
            !pasteboard.setString(String(decoding: data, as: UTF8.self), forType: .string)
        {
            throw .pasteboardWriteFailed
        }
    }

    private func copyFromContextMenu(_ format: DiagramExportFormat) {
        Task { [weak self] in
            guard let self else { return }
            do throws(ExportError) {
                try await copyDiagram(format)
            } catch {
                exportErrorHandler?(error)
            }
        }
    }

    func refreshCurrentSource() {
        guard mermaidReady else {
            recoveryAttempts = 0
            reloadRuntime()
            return
        }
        render(source: lastSource, force: true)
    }

    func render(source: String, force: Bool = false) {
        guard force || source != lastSource else { return }
        lastSource = source
        renderRevision &+= 1
        let requestedRevision = renderRevision
        updatePreviewStatus()
        let isEmpty = source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        state = isEmpty ? .idle : .rendering

        renderTask?.cancel()

        guard isLivePreviewEnabled || force || isEmpty else {
            state = hasDiagram ? .ready : .idle
            return
        }

        guard mermaidReady else {
            logger.info("Mermaid not ready, queueing render")
            validator.scheduleValidation()
            return
        }

        renderTask = Task { [weak self] in
            guard let self else { return }
            if source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                await performRender(source: source, revision: requestedRevision)
                return
            }

            do {
                try await Task.sleep(for: debounceInterval)
            } catch {
                return
            }

            await performRender(source: source, revision: requestedRevision)
        }
    }

    private func performRender(source: String, revision: UInt64) async {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            state = .idle
            do {
                try await clearDiagram()
                guard revision == renderRevision else { return }
                successfulRevision = nil
                updatePreviewStatus()
            } catch {
                logger.error("Failed to clear diagram: \(error.localizedDescription, privacy: .public)")
                guard revision == renderRevision else { return }
                state = .failure(error: MermaidError(message: error.localizedDescription, line: nil))
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
                arguments: ["source": source],
                contentWorld: .page
            )

            guard !Task.isCancelled, revision == renderRevision else { return }

            guard let dict = result as? [String: Any], let success = dict["success"] as? Bool else {
                let message = "Preview runtime returned an unexpected render response."
                logger.error("\(message, privacy: .public)")
                state = .failure(error: MermaidError(message: message, line: nil))
                await validator.auditDOM(context: "malformed-render-response")
                return
            }

            if success {
                if dict["stale"] as? Bool == true {
                    logger.debug("Dropping stale render result")
                    return
                }

                if var metrics = await validator.fetchMetrics() {
                    guard !Task.isCancelled, revision == renderRevision else { return }
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
                        do {
                            try await Task.sleep(for: .milliseconds(100))
                        } catch {
                            return
                        }
                        guard !Task.isCancelled else { return }
                        if let retry = await validator.fetchMetrics(),
                            retry.hasSVG
                        {
                            metrics = retry
                        }
                        guard !Task.isCancelled, revision == renderRevision else { return }
                    }

                    if viewHasSize && (metrics.width <= 1 || metrics.height <= 1) {
                        let message = "Rendered SVG has invalid size (\(metrics.width)x\(metrics.height))."
                        logger.error("\(message, privacy: .public)")
                        state = .failure(error: MermaidError(message: message, line: nil))
                        return
                    }
                }

                guard !Task.isCancelled, revision == renderRevision else { return }
                logger.info("Render succeeded")
                successfulRevision = revision
                updatePreviewStatus()
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
            if !Task.isCancelled, revision == renderRevision, mermaidReady {
                logger.error("Render failed: \(error.localizedDescription)")
                state = .failure(error: MermaidError(message: error.localizedDescription, line: nil))
                await validator.auditDOM(context: "render-error")
            }
        }
    }

    private func clearDiagram() async throws {
        try await webView.evaluateJavaScript("window.clearDiagram();")
    }

    private func loadBaseHTML() {
        guard let previewURL = Bundle.appResource(name: "preview", extension: "html") else {
            logger.error("Failed to find bundled preview.html")
            state = .failure(error: MermaidError(message: "Missing preview renderer resource", line: nil))
            return
        }

        let normalizedPreviewURL = DiagramSecurityPolicy.normalizedFileURL(previewURL)
        validator.trustedPreviewFiles = [normalizedPreviewURL]
        webView.loadFileURL(
            normalizedPreviewURL, allowingReadAccessTo: normalizedPreviewURL.deletingLastPathComponent())
    }

    func handleMermaidReady() {
        guard !mermaidReady else { return }
        mermaidReady = true
        recoveryAttempts = 0
        Task { [weak self] in
            guard let self else { return }
            guard await applyThemeToRuntime() else { return }
            await applyZoom(level: zoomLevel)
            render(source: lastSource, force: true)
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

    private func updatePreviewStatus() {
        hasDiagram = successfulRevision != nil
        isPreviewStale = hasDiagram && successfulRevision != renderRevision
        canExport = hasDiagram && !isPreviewStale
    }

    private func recoverRenderer(after message: String) {
        guard recoveryAttempts < maximumRecoveryAttempts else {
            logger.error("Renderer recovery exhausted after: \(message, privacy: .public)")
            state = .failure(error: MermaidError(message: "Failed to load renderer", line: nil))
            return
        }

        recoveryAttempts += 1
        logger.error("Recovering preview renderer after: \(message, privacy: .public)")
        reloadRuntime()
    }

    private func reloadRuntime() {
        renderTask?.cancel()
        validator.cancelValidation()
        mermaidReady = false
        renderRevision &+= 1
        successfulRevision = nil
        updatePreviewStatus()
        state = hasSourceContent() ? .rendering : .idle
        loadBaseHTML()
    }
}

extension MermaidRenderer: WKScriptMessageHandler {
    func userContentController(
        _ controller: WKUserContentController, didReceive message: WKScriptMessage
    ) {
        guard message.frameInfo.isMainFrame else { return }
        switch message.name {
        case "ready":
            handleMermaidReady()
        case "zoomChanged":
            handleZoomChangedMessage(message.body)
        case "appearanceChanged":
            if theme == .auto {
                refreshCurrentSource()
            }
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
        decisionHandler(
            DiagramSecurityPolicy.navigationPolicy(
                for: navigationAction.request.url,
                trustedLocalFiles: validator.trustedPreviewFiles
            ))
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            validator.scheduleValidation()
        }
    }

    nonisolated func webView(
        _ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error
    ) {
        Task { @MainActor in
            recoverRenderer(after: "navigation failed: \(error.localizedDescription)")
        }
    }

    nonisolated func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        Task { @MainActor in
            recoverRenderer(after: "provisional navigation failed: \(error.localizedDescription)")
        }
    }

    nonisolated func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        Task { @MainActor in
            recoverRenderer(after: "web content process terminated")
        }
    }
}

extension MermaidRenderer {
    internal func applyTheme() {
        guard mermaidReady else { return }

        renderTask?.cancel()
        renderRevision &+= 1
        let requestedRevision = renderRevision
        let source = lastSource
        updatePreviewStatus()
        state = source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .idle : .rendering

        renderTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard await applyThemeToRuntime() else { return }
            guard requestedRevision == renderRevision else { return }
            await performRender(source: source, revision: requestedRevision)
        }
    }

    private func applyThemeToRuntime() async -> Bool {
        do {
            _ = try await webView.callAsyncJavaScript(
                "window.setTheme(themeName);",
                arguments: ["themeName": theme.rawValue],
                contentWorld: .page
            )
            return true
        } catch {
            logger.error(
                "Failed to apply preview theme '\(self.theme.rawValue, privacy: .public)': \(error.localizedDescription, privacy: .public)"
            )
            state = .failure(
                error: MermaidError(
                    message: "Failed to apply theme '\(self.theme.rawValue)': \(error.localizedDescription)",
                    line: nil))
            return false
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
            logger.error(
                "Failed to set zoom to \(level, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    func handleZoomChangedMessage(_ body: Any) {
        guard let rawLevel = coerceToDouble(body) else {
            logger.error(
                "zoomChanged bridge payload is invalid: \(String(describing: body), privacy: .public)")
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

private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: (any WKScriptMessageHandler)?

    init(delegate: any WKScriptMessageHandler) {
        self.delegate = delegate
    }

    func userContentController(
        _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
    ) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}
