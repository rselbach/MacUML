import WebKit
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
