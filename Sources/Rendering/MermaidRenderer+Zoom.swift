import Foundation
import WebKit

extension MermaidRenderer {
    private static let zoomEpsilon: Double = 0.0001

    func zoomIn() {
        setZoom(zoomLevel + zoomStep)
    }

    func zoomOut() {
        setZoom(zoomLevel - zoomStep)
    }

    func resetZoom() {
        setZoom(1.0)
    }

    internal func setZoom(_ newLevel: Double) {
        let rounded = (clampZoom(newLevel) * 100).rounded() / 100
        zoomLevel = rounded

        guard mermaidReady else { return }
        Task {
            await applyZoom(level: rounded)
        }
    }

    internal func clampZoom(_ level: Double) -> Double {
        min(max(level, minZoom), maxZoom)
    }

    internal func applyZoom(level: Double) async {
        do {
            _ = try await webView.callAsyncJavaScript(
                "window.setZoom(level);",
                arguments: ["level": level],
                contentWorld: .page
            )
        } catch {
            logger.error("Failed to set zoom to \(level, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    func handleZoomChangedMessage(_ body: Any) {
        guard let rawLevel = coerceToDouble(body) else {
            logger.error("zoomChanged bridge payload is invalid: \(String(describing: body), privacy: .public)")
            return
        }

        let normalized = (clampZoom(rawLevel) * 100).rounded() / 100
        guard abs(normalized - zoomLevel) >= Self.zoomEpsilon else {
            return
        }

        zoomLevel = normalized
    }

    private func coerceToDouble(_ value: Any) -> Double? {
        (value as? NSNumber)?.doubleValue ?? value as? Double ?? Double(value as? String ?? "")
    }
}
