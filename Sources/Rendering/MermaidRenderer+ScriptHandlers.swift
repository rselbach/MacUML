import Foundation
import WebKit

/// Generic script message handler that validates message name and main frame before invoking action.
final class ScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var renderer: MermaidRenderer?
    private let messageName: String
    private let action: @MainActor (MermaidRenderer, Any) -> Void

    init(
        renderer: MermaidRenderer,
        name: String,
        action: @escaping @MainActor (MermaidRenderer, Any) -> Void
    ) {
        self.renderer = renderer
        self.messageName = name
        self.action = action
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == messageName, message.frameInfo.isMainFrame else { return }
        Task { @MainActor [weak self] in
            guard let self, let renderer = self.renderer else { return }
            self.action(renderer, message.body)
        }
    }
}
