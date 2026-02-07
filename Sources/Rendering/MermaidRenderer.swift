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
    private let debounceInterval: Duration = .milliseconds(300)
    private let logger = Logger(subsystem: "com.macuml", category: "mermaid")
    private var mermaidReady = false
    private var pendingSource: String?
    private let enablePreviewDiagnostics: Bool = {
#if DEBUG
        true
#else
        false
#endif
    }()

    override init() {
        let config = WKWebViewConfiguration()
#if DEBUG
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
#endif
        
        let contentController = WKUserContentController()
        config.userContentController = contentController
        
        webView = DiagramWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")

        super.init()
        
        if let savedTheme = MermaidTheme(rawValue: AppSettings.shared.defaultDiagramTheme) {
            theme = savedTheme
        }

        contentController.add(ReadyHandler(renderer: self), name: "ready")
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
                    logger.info("Render succeeded")
                    state = .ready
                    currentError = nil
                } else if let error = dict["error"] as? String {
                    logger.info("Render failed")
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

            if enablePreviewDiagnostics {
                await auditPreviewDOM(context: "post-render")
            }
        } catch {
            if !Task.isCancelled {
                logger.error("Render failed: \(error.localizedDescription)")
                state = .failure(error.localizedDescription)
                if enablePreviewDiagnostics {
                    await auditPreviewDOM(context: "render-error")
                }
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
        // Try Bundle.main first (for app bundles), then Bundle.module (for swift run)
        let mermaidURL: URL? = Bundle.main.url(forResource: "mermaid.min", withExtension: "js")
            ?? Bundle.module.url(forResource: "mermaid.min", withExtension: "js")
        
        guard let mermaidURL else {
            logger.error("Failed to find bundled mermaid.min.js")
            state = .failure("Missing mermaid.min.js resource")
            return
        }
        
        let html = """
            <!DOCTYPE html>
            <html>
            <head>
                <meta charset="UTF-8">
                <meta name="viewport" content="width=device-width, initial-scale=1.0">
                <script src="mermaid.min.js"></script>
                <script>
                    window.currentTheme = 'auto';
                    window.renderSequence = 0;

                    function collectUnexpectedBodyNodes() {
                        const diagram = document.getElementById('diagram');
                        if (!diagram) return [];
                        return Array.from(document.body.childNodes).filter((node) => {
                            if (node === diagram) return false;
                            if (node instanceof Element &&
                                node.getAttribute('data-macuml-role') === 'temp-render') {
                                return false;
                            }
                            if (node.nodeType === Node.TEXT_NODE) {
                                return (node.textContent || '').trim().length > 0;
                            }
                            return true;
                        });
                    }

                    function cleanupUnexpectedBodyNodes(reason) {
                        const unexpectedNodes = collectUnexpectedBodyNodes();
                        if (unexpectedNodes.length === 0) return;

                        console.warn('[MermaidPreview] Removing unexpected body nodes', {
                            reason,
                            count: unexpectedNodes.length
                        });
                        unexpectedNodes.forEach((node) => node.remove());
                    }

                    window.collectPreviewDiagnostics = function() {
                        const unexpectedNodes = collectUnexpectedBodyNodes();
                        return {
                            extraNodeCount: unexpectedNodes.length
                        };
                    };
                    
                    function getEffectiveTheme() {
                        if (window.currentTheme === 'auto') {
                            return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'default';
                        }
                        return window.currentTheme;
                    }
                    
                    function initMermaid() {
                        mermaid.initialize({
                            startOnLoad: false,
                            theme: getEffectiveTheme(),
                            securityLevel: 'strict',
                            fontFamily: 'system-ui, -apple-system, sans-serif'
                        });
                    }
                    
                    function updateBackground() {
                        const theme = getEffectiveTheme();
                        const container = document.getElementById('diagram');
                        const useDark = theme === 'dark' || 
                            (window.currentTheme === 'auto' && window.matchMedia('(prefers-color-scheme: dark)').matches);
                        container.className = useDark ? 'dark-bg' : 'light-bg';
                    }
                    
                    document.addEventListener('DOMContentLoaded', () => {
                        initMermaid();
                        updateBackground();
                        cleanupUnexpectedBodyNodes('DOMContentLoaded');

                        const observer = new MutationObserver((mutations) => {
                            let hasUnexpectedMutation = false;
                            const diagram = document.getElementById('diagram');

                            for (const mutation of mutations) {
                                for (const addedNode of mutation.addedNodes) {
                                    if (!diagram) continue;
                                    if (addedNode === diagram) continue;
                                    if (diagram.contains(addedNode)) continue;
                                    if (addedNode instanceof Element &&
                                        addedNode.getAttribute('data-macuml-role') === 'temp-render') {
                                        continue;
                                    }
                                    if (addedNode.nodeType === Node.TEXT_NODE &&
                                        (addedNode.textContent || '').trim().length === 0) {
                                        continue;
                                    }
                                    hasUnexpectedMutation = true;
                                    break;
                                }
                                if (hasUnexpectedMutation) break;
                            }

                            if (hasUnexpectedMutation) {
                                cleanupUnexpectedBodyNodes('mutation-observer');
                            }
                        });
                        observer.observe(document.body, { childList: true });

                        window.webkit.messageHandlers.ready.postMessage(true);
                    });
                    
                    window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => {
                        if (window.currentTheme === 'auto') {
                            initMermaid();
                            updateBackground();
                            if (window.lastSource) {
                                window.renderDiagram(window.lastSource);
                            }
                        }
                    });
                    
                    window.setTheme = function(theme) {
                        window.currentTheme = theme;
                        initMermaid();
                        updateBackground();
                    };
                    
                    window.rescaleSVG = function() {
                        const container = document.getElementById('diagram');
                        const svgEl = container.querySelector('svg');
                        if (!svgEl) return;
                        
                        svgEl.removeAttribute('style');
                        svgEl.style.maxWidth = '100%';
                        svgEl.style.maxHeight = '100%';
                        svgEl.style.width = 'auto';
                        svgEl.style.height = 'auto';
                    };
                    
                    new ResizeObserver(() => window.rescaleSVG()).observe(document.documentElement);

                    window.renderDiagram = async function(source) {
                        window.lastSource = source;
                        const renderSequence = ++window.renderSequence;
                        const container = document.getElementById('diagram');
                        const tempContainer = document.createElement('div');
                        tempContainer.style.position = 'fixed';
                        tempContainer.style.left = '-10000px';
                        tempContainer.style.top = '0';
                        tempContainer.style.visibility = 'hidden';
                        tempContainer.style.pointerEvents = 'none';
                        tempContainer.setAttribute('data-macuml-role', 'temp-render');
                        tempContainer.setAttribute('aria-hidden', 'true');
                        document.body.appendChild(tempContainer);
                        
                        try {
                            const id = 'mermaid-' + renderSequence + '-' + Date.now();
                            const { svg } = await mermaid.render(id, source, tempContainer);
                            if (renderSequence !== window.renderSequence) {
                                return { success: true, stale: true };
                            }
                            
                            // Check for actual syntax/parse errors (mermaid exceptions produce specific patterns)
                            const hasError = svg.includes('Syntax error') || svg.includes('Parse error');
                            
                            if (svg && !hasError) {
                                container.innerHTML = svg;
                                requestAnimationFrame(() => window.rescaleSVG());
                                cleanupUnexpectedBodyNodes('render-success');
                                return { success: true };
                            } else {
                                const errorText = tempContainer.textContent || 'Syntax error in diagram';
                                cleanupUnexpectedBodyNodes('render-error-content');
                                return { success: false, error: errorText.trim().substring(0, 200) };
                            }
                        } catch (e) {
                            let line = null;
                            const msg = e.message || String(e);
                            
                            // Try various line number patterns
                            const patterns = [
                                /line\\s*(\\d+)/i,
                                /on line (\\d+)/i,
                                /at line (\\d+)/i,
                                /:(\\d+):/,
                                /\\((\\d+):(\\d+)\\)/
                            ];
                            
                            for (const pattern of patterns) {
                                const match = msg.match(pattern);
                                if (match) {
                                    line = parseInt(match[1], 10);
                                    break;
                                }
                            }
                            
                            return { success: false, error: msg, line: line };
                        } finally {
                            tempContainer.remove();
                            cleanupUnexpectedBodyNodes('render-finally');
                        }
                    };
                </script>
                <style>
                    * { margin: 0; padding: 0; box-sizing: border-box; }
                    html, body {
                        height: 100%;
                    }
                    body {
                        font-family: system-ui, -apple-system, sans-serif;
                        background: transparent;
                        display: flex;
                        justify-content: center;
                        align-items: center;
                        padding: 0;
                    }
                    #diagram {
                        width: 100vw;
                        height: 100vh;
                        border-radius: 4px;
                        padding: 4px;
                        display: flex;
                        justify-content: center;
                        align-items: center;
                        overflow: hidden;
                    }
                    #diagram.light-bg {
                        background: white;
                    }
                    #diagram.dark-bg {
                        background: #1e1e1e;
                    }
                    #diagram svg {
                        max-width: 100%;
                        max-height: 100%;
                    }
                    .error {
                        color: #ff6b6b;
                        padding: 1em;
                        white-space: pre-wrap;
                        word-break: break-word;
                    }
                </style>
            </head>
            <body>
                <div id="diagram"></div>
            </body>
            </html>
            """
        webView.loadHTMLString(html, baseURL: mermaidURL.deletingLastPathComponent())
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

            logger.error(
                "Preview DOM audit (\(context, privacy: .public)): extra nodes=\(extraNodeCount, privacy: .public)"
            )
        } catch {
            logger.error("Preview DOM audit failed (\(context, privacy: .public))")
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
        let js = "document.getElementById('diagram').innerHTML"
        do {
            let result = try await webView.evaluateJavaScript(js)
            return result as? String
        } catch {
            logger.error("SVG extraction failed: \(error.localizedDescription)")
            return nil
        }
    }
    func handleMermaidReady() {
        mermaidReady = true
        applyTheme()
        if let source = pendingSource {
            pendingSource = nil
            render(source: source, force: true)
        }
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

extension MermaidRenderer: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        guard let requestURL = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }

        if requestURL.isFileURL || requestURL.scheme == "about" {
            decisionHandler(.allow)
            return
        }

        decisionHandler(.cancel)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Don't render here - wait for mermaid ready signal instead
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        logger.error("Navigation failed: \(error.localizedDescription)")
        state = .failure("Failed to load renderer")
    }
}
