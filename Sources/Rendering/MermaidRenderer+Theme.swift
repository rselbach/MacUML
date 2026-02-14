import Foundation
import WebKit

extension MermaidRenderer {
    internal func applyTheme() {
        Task {
            do {
                _ = try await webView.callAsyncJavaScript(
                    "window.setTheme(themeName);",
                    arguments: ["themeName": self.theme.rawValue],
                    contentWorld: .page
                )
            } catch {
                self.logger.error("Failed to apply preview theme '\(self.theme.rawValue, privacy: .public)': \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
