import Foundation
import WebKit
import AppKit

extension MermaidRenderer {
    func copyAsPNG() async -> Data? {
        let config = WKSnapshotConfiguration()
        config.afterScreenUpdates = true

        if let rect = await getDiagramBounds() {
            let padding: CGFloat = 16
            let paddedRect = CGRect(
                x: max(0, rect.origin.x - padding),
                y: max(0, rect.origin.y - padding),
                width: rect.width + padding * 2,
                height: rect.height + padding * 2
            )
            let viewBounds = webView.bounds
            config.rect = paddedRect.intersection(viewBounds)
        }

        do {
            let image = try await webView.takeSnapshot(configuration: config)
            guard let tiffData = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData),
                  let pngData = bitmap.representation(using: .png, properties: [:]) else {
                return nil
            }
            return pngData
        } catch {
            logger.error("Snapshot failed: \(error.localizedDescription)")
            return nil
        }
    }

    internal func getDiagramBounds() async -> CGRect? {
        let js = """
            (function() {
                const svg = document.querySelector('#diagram svg');
                if (!svg) return null;
                const rect = svg.getBoundingClientRect();
                return { x: rect.x, y: rect.y, width: rect.width, height: rect.height };
            })()
            """
        do {
            guard let result = try await webView.evaluateJavaScript(js) as? [String: Any],
                  let x = result["x"] as? Double,
                  let y = result["y"] as? Double,
                  let width = result["width"] as? Double,
                  let height = result["height"] as? Double else {
                return nil
            }
            return CGRect(x: x, y: y, width: width, height: height)
        } catch {
            logger.error("Failed to get diagram bounds: \(error.localizedDescription)")
            return nil
        }
    }

    func copySVG() async -> String? {
        let js = """
            (function() {
                const svg = document.querySelector('#diagram svg');
                return svg ? svg.outerHTML : '';
            })()
            """
        do {
            let result = try await webView.evaluateJavaScript(js)
            return result as? String
        } catch {
            logger.error("SVG extraction failed: \(error.localizedDescription)")
            return nil
        }
    }
}
