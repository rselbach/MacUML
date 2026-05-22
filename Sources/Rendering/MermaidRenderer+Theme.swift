import Foundation
import WebKit

extension MermaidRenderer {
    internal func applyTheme() {
        guard mermaidReady else {
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                _ = try await webView.callAsyncJavaScript(
                    "window.setTheme(themeName);",
                    arguments: ["themeName": self.theme.rawValue],
                    contentWorld: .page
                )
            } catch {
                self.logger.error("Failed to apply preview theme '\(self.theme.rawValue, privacy: .public)': \(error.localizedDescription, privacy: .public)")
                self.state = .failure(error: MermaidError(message: "Failed to apply theme '\(self.theme.rawValue)': \(error.localizedDescription)", line: nil))
            }
        }
    }
}
