import WebKit
import AppKit

/// A WKWebView subclass customized for diagram display with custom context menu.
///
/// Provides PNG and SVG export handlers via the context menu,
/// allowing users to copy diagram images to the clipboard.
@MainActor
class DiagramWebView: WKWebView {
    /// Handler called when user selects "Copy as PNG" from context menu.
    var copyPNGHandler: (() -> Void)?
    /// Handler called when user selects "Copy as SVG" from context menu.
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
