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

    override init() {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        
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
                    logger.info("Render succeeded")
                    state = .ready
                    currentError = nil
                } else if let error = dict["error"] as? String {
                    logger.info("Render failed: \(error)")
                    let line = dict["line"] as? Int
                    currentError = MermaidError(message: error, line: line)
                }
            } else {
                state = .ready
            }
        } catch {
            if !Task.isCancelled {
                logger.error("Render failed: \(error.localizedDescription)")
                state = .failure(error.localizedDescription)
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
                            securityLevel: 'loose',
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
                        
                        svgEl.style.transform = 'none';
                        const bbox = svgEl.getBBox();
                        const pad = 8;
                        const containerW = container.clientWidth;
                        const containerH = container.clientHeight;
                        const scaleX = containerW / (bbox.width + pad * 2);
                        const scaleY = containerH / (bbox.height + pad * 2);
                        const scale = Math.min(scaleX, scaleY, 3);
                        svgEl.style.transform = `scale(${scale})`;
                        svgEl.style.transformOrigin = 'center center';
                    };
                    
                    new ResizeObserver(() => window.rescaleSVG()).observe(document.documentElement);

                    window.renderDiagram = async function(source) {
                        window.lastSource = source;
                        const container = document.getElementById('diagram');
                        const tempContainer = document.getElementById('temp-render');
                        
                        tempContainer.innerHTML = '';
                        
                        try {
                            const id = 'mermaid-' + Date.now();
                            const { svg } = await mermaid.render(id, source, tempContainer);
                            
                            // Check for actual syntax/parse errors (mermaid exceptions produce specific patterns)
                            const hasError = svg.includes('Syntax error') || svg.includes('Parse error');
                            
                            if (svg && !hasError) {
                                container.innerHTML = svg;
                                requestAnimationFrame(() => window.rescaleSVG());
                                return { success: true };
                            } else {
                                const errorText = tempContainer.textContent || 'Syntax error in diagram';
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
                            tempContainer.innerHTML = '';
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
                        padding: 8px;
                    }
                    #diagram {
                        width: calc(100vw - 16px);
                        height: calc(100vh - 16px);
                        border-radius: 8px;
                        padding: 8px;
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
                <div id="temp-render" style="position: absolute; left: -9999px; visibility: hidden;"></div>
            </body>
            </html>
            """
        webView.loadHTMLString(html, baseURL: mermaidURL.deletingLastPathComponent())
    }

    func copyAsPNG() async -> Data? {
        let config = WKSnapshotConfiguration()
        config.afterScreenUpdates = true

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
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Don't render here - wait for mermaid ready signal instead
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            logger.error("Navigation failed: \(error.localizedDescription)")
            state = .failure("Failed to load renderer")
        }
    }
}
