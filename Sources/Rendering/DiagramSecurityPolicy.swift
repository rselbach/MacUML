import Foundation
import WebKit

/// Security policy for WebView navigation decisions.
enum DiagramSecurityPolicy {
    /// Normalizes a file URL for reliable comparison.
    nonisolated static func normalizedFileURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    /// Determines navigation policy for a URL against trusted files.
    nonisolated static func navigationPolicy(
        for requestURL: URL?,
        trustedLocalFiles: Set<URL>
    ) -> WKNavigationActionPolicy {
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
}