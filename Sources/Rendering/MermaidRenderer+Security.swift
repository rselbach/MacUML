import Foundation
import WebKit

extension MermaidRenderer {
    nonisolated static func normalizedFileURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    nonisolated static func navigationPolicy(for requestURL: URL?, trustedLocalFiles: Set<URL>) -> WKNavigationActionPolicy {
        guard let requestURL else {
            return .cancel
        }

        if requestURL.scheme == "about" {
            let aboutURL = requestURL.absoluteString.lowercased()
            return (aboutURL == "about:blank" || aboutURL == "about:srcdoc") ? .allow : .cancel
        }

        guard requestURL.isFileURL else {
            return .cancel
        }

        let normalizedRequestURL = normalizedFileURL(requestURL)
        return trustedLocalFiles.contains(normalizedRequestURL) ? .allow : .cancel
    }

    nonisolated static func navigationPolicy(for requestURL: URL?) -> WKNavigationActionPolicy {
        navigationPolicy(for: requestURL, trustedLocalFiles: [])
    }
}

extension MermaidRenderer: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        decisionHandler(Self.navigationPolicy(for: navigationAction.request.url, trustedLocalFiles: trustedPreviewFiles))
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            schedulePreviewRuntimeValidation()
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            logger.error("Navigation failed: \(error.localizedDescription)")
            state = .failure("Failed to load renderer")
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
