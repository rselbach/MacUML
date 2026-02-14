import Foundation
import WebKit
import os

extension MermaidRenderer: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        decisionHandler(DiagramSecurityPolicy.navigationPolicy(
            for: navigationAction.request.url,
            trustedLocalFiles: trustedPreviewFiles
        ))
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            schedulePreviewRuntimeValidation()
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            logger.error("Navigation failed: \(error.localizedDescription)")
            state = .failure(message: "Failed to load renderer")
        }
    }
}

extension MermaidRenderer: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        nil
    }
}