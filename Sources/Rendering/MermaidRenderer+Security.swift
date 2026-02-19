import Foundation
import WebKit

extension MermaidRenderer: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        decisionHandler(DiagramSecurityPolicy.navigationPolicy(
            for: navigationAction.request.url,
            trustedLocalFiles: validator.trustedPreviewFiles
        ))
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            validator.scheduleValidation()
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            logger.error("Navigation failed: \(error.localizedDescription)")
            state = .failure(error: MermaidError(message: "Failed to load renderer", line: nil))
        }
    }
}