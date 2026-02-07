import Foundation
import WebKit

extension MermaidRenderer {
    internal func applyTheme() {
        let js = "window.setTheme('\(theme.rawValue)');"
        webView.evaluateJavaScript(js) { [weak self] _, error in
            guard let self else { return }

            if let error {
                self.logger.error("Failed to apply preview theme '\(self.theme.rawValue, privacy: .public)': \(error.localizedDescription, privacy: .public)")
                return
            }

            guard !self.lastSource.isEmpty else { return }
            Task { @MainActor in
                await self.performRender(source: self.lastSource)
            }
        }
    }
}
