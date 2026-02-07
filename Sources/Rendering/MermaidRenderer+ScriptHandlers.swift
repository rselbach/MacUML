import Foundation
import WebKit

class ReadyHandler: NSObject, WKScriptMessageHandler {
    weak var renderer: MermaidRenderer?
    init(renderer: MermaidRenderer) { self.renderer = renderer }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "ready", message.frameInfo.isMainFrame else {
            return
        }

        Task { @MainActor in
            renderer?.handleMermaidReady()
        }
    }
}

class ZoomChangedHandler: NSObject, WKScriptMessageHandler {
    weak var renderer: MermaidRenderer?

    init(renderer: MermaidRenderer) {
        self.renderer = renderer
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "zoomChanged", message.frameInfo.isMainFrame else {
            return
        }

        Task { @MainActor in
            renderer?.handleZoomChangedMessage(message.body)
        }
    }
}
