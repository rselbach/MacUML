import Foundation
import WebKit

extension MermaidRenderer {
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
        let js = "window.setZoom(\(level));"
        do {
            let result = try await webView.evaluateJavaScript(js)
            if let zoom = result as? Double {
                zoomLevel = zoom
                return
            }

            if let zoom = result as? NSNumber {
                zoomLevel = zoom.doubleValue
            }
        } catch {
            logger.error("Failed to set zoom to \(level, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    func handleZoomChangedMessage(_ body: Any) {
        let rawLevel: Double

        if let value = body as? NSNumber {
            rawLevel = value.doubleValue
        } else if let value = body as? Double {
            rawLevel = value
        } else if let value = body as? String, let parsed = Double(value) {
            rawLevel = parsed
        } else {
            logger.error("zoomChanged bridge payload is invalid: \(String(describing: body), privacy: .public)")
            return
        }

        let normalized = (clampZoom(rawLevel) * 100).rounded() / 100
        guard abs(normalized - zoomLevel) >= 0.0001 else {
            return
        }

        zoomLevel = normalized
    }
}
