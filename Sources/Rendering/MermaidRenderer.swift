import Foundation
import WebKit
import Combine
import os

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
    let webView: WKWebView
    private var lastSource: String = ""
    private var renderTask: Task<Void, Never>?
    private let debounceInterval: Duration = .milliseconds(300)
    private let logger = Logger(subsystem: "com.macuml", category: "mermaid")

    override init() {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")

        super.init()

        webView.navigationDelegate = self
        loadBaseHTML()
    }

    func render(source: String, force: Bool = false) {
        guard force || source != lastSource else { return }
        lastSource = source

        renderTask?.cancel()
        currentError = nil

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

        let js = "await window.renderDiagram(source);"

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
                    state = .ready
                    currentError = nil
                } else if let error = dict["error"] as? String {
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
        let html = """
            <!DOCTYPE html>
            <html>
            <head>
                <meta charset="UTF-8">
                <meta name="viewport" content="width=device-width, initial-scale=1.0">
                <script type="module">
                    import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs';
                    
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
                    
                    initMermaid();
                    updateBackground();
                    
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

                    window.renderDiagram = async function(source) {
                        window.lastSource = source;
                        const container = document.getElementById('diagram');
                        const tempContainer = document.getElementById('temp-render');
                        
                        tempContainer.innerHTML = '';
                        
                        try {
                            const id = 'mermaid-' + Date.now();
                            const { svg } = await mermaid.render(id, source, tempContainer);
                            
                            // Check for error indicators in SVG
                            const hasError = svg && (
                                svg.includes('Syntax error') ||
                                svg.includes('error-icon') ||
                                svg.includes('error-text') ||
                                svg.includes('Parse error') ||
                                tempContainer.querySelector('.error-icon, .error-text, [class*="error"]')
                            );
                            
                            if (svg && !hasError) {
                                container.innerHTML = svg;
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
                    body {
                        font-family: system-ui, -apple-system, sans-serif;
                        background: transparent;
                        display: flex;
                        justify-content: center;
                        padding: 20px;
                    }
                    #diagram {
                        max-width: 100%;
                        border-radius: 8px;
                        padding: 16px;
                    }
                    #diagram.light-bg {
                        background: white;
                    }
                    #diagram.dark-bg {
                        background: #1e1e1e;
                    }
                    #diagram svg {
                        max-width: 100%;
                        height: auto;
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
        webView.loadHTMLString(html, baseURL: nil)
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
}

extension MermaidRenderer: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            if !lastSource.isEmpty {
                await performRender(source: lastSource)
            }
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            logger.error("Navigation failed: \(error.localizedDescription)")
            state = .failure("Failed to load renderer")
        }
    }
}
