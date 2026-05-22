import WebKit
import AppKit
import os

@MainActor
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

    func fetchDiagramBounds() async -> CGRect? {
        let js = """
            (function() {
                const svg = document.querySelector('#diagram svg');
                if (!svg) return null;
                const rect = svg.getBoundingClientRect();
                return { x: rect.x, y: rect.y, width: rect.width, height: rect.height };
            })()
            """
        do {
            guard let result = try await evaluateJavaScript(js) as? [String: Any],
                  let x = result["x"] as? Double,
                  let y = result["y"] as? Double,
                  let width = result["width"] as? Double,
                  let height = result["height"] as? Double else {
                return nil
            }
            return CGRect(x: x, y: y, width: width, height: height)
        } catch {
            Logger(subsystem: "com.macuml", category: "webview").error("Failed to fetch diagram bounds: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func fetchDiagramMetrics() async -> DiagramMetrics? {
        guard let bounds = await fetchDiagramBounds() else {
            return DiagramMetrics(hasSVG: false, width: 0, height: 0)
        }
        return DiagramMetrics(hasSVG: true, width: bounds.width, height: bounds.height)
    }

    @objc private func handleCopyPNG() {
        copyPNGHandler?()
    }

    @objc private func handleCopySVG() {
        copySVGHandler?()
    }
}
