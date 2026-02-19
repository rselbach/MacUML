import AppKit
import Foundation
import os
import WebKit

enum ExportError: LocalizedError, Equatable {
    case snapshotFailed(Error)
    case imageConversionFailed
    case svgExtractionFailed(Error)
    case svgNotFound
    case noDiagram

    static func == (lhs: ExportError, rhs: ExportError) -> Bool {
        switch (lhs, rhs) {
        case (.imageConversionFailed, .imageConversionFailed),
             (.svgNotFound, .svgNotFound),
             (.noDiagram, .noDiagram):
            true
        case (.snapshotFailed(let l), .snapshotFailed(let r)):
            l.localizedDescription == r.localizedDescription
        case (.svgExtractionFailed(let l), .svgExtractionFailed(let r)):
            l.localizedDescription == r.localizedDescription
        default:
            false
        }
    }

    var errorDescription: String? {
        switch self {
        case .snapshotFailed(let error):
            "Failed to capture diagram: \(error.localizedDescription)"
        case .imageConversionFailed:
            "Failed to convert diagram to PNG format"
        case .svgExtractionFailed(let error):
            "Failed to extract SVG: \(error.localizedDescription)"
        case .svgNotFound:
            "No SVG diagram found to export"
        case .noDiagram:
            "No diagram available to export"
        }
    }
}

@MainActor
struct DiagramExporter {
    let webView: DiagramWebView
    private let logger = Logging.logger(category: "exporter")

    func copyAsPNG(padding: CGFloat = 16) async -> Result<Data, ExportError> {
        let config = WKSnapshotConfiguration()
        config.afterScreenUpdates = true

        if let rect = await getDiagramBounds() {
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
            guard let tiffData = image.tiffRepresentation else {
                logger.error("PNG export failed: could not create TIFF representation")
                return .failure(.imageConversionFailed)
            }
            guard let bitmap = NSBitmapImageRep(data: tiffData) else {
                logger.error("PNG export failed: could not create bitmap from TIFF")
                return .failure(.imageConversionFailed)
            }
            guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
                logger.error("PNG export failed: could not create PNG data")
                return .failure(.imageConversionFailed)
            }
            logger.info("PNG export succeeded")
            return .success(pngData)
        } catch {
            logger.error("Snapshot failed: \(error.localizedDescription)")
            return .failure(.snapshotFailed(error))
        }
    }

    func copySVG() async -> Result<String, ExportError> {
        let js = """
            (function() {
                const svg = document.querySelector('#diagram svg');
                return svg ? svg.outerHTML : '';
            })()
            """
        do {
            let result = try await webView.evaluateJavaScript(js)
            guard let rawSvg = result as? String else {
                logger.error("SVG extraction failed: unexpected type \(type(of: result))")
                return .failure(.svgExtractionFailed(NSError(domain: "DiagramExporter", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unexpected result type"])))
            }
            guard !rawSvg.isEmpty else {
                logger.error("SVG extraction failed: no SVG element found")
                return .failure(.svgNotFound)
            }
            
            // Defense-in-depth: strip `<script>` tags and `on*` attributes from exported SVG
            var sanitizedSvg = rawSvg.replacingOccurrences(
                of: "(?is)<script\\b[^>]*>.*?</script>",
                with: "",
                options: .regularExpression
            )
            sanitizedSvg = sanitizedSvg.replacingOccurrences(
                of: "(?i)\\bon[a-z]+\\s*=\\s*\"[^\"]*\"",
                with: "",
                options: .regularExpression
            )
            sanitizedSvg = sanitizedSvg.replacingOccurrences(
                of: "(?i)\\bon[a-z]+\\s*=\\s*'[^']*'",
                with: "",
                options: .regularExpression
            )
            
            logger.info("SVG export succeeded")
            return .success(sanitizedSvg)
        } catch {
            logger.error("SVG extraction failed: \(error.localizedDescription)")
            return .failure(.svgExtractionFailed(error))
        }
    }

    private func getDiagramBounds() async -> CGRect? {
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
}