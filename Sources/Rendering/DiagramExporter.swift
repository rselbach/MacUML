import Foundation
import WebKit
import os

enum ExportError: LocalizedError, Equatable {
    case rasterizationFailed(String)
    case invalidPNGData
    case pasteboardWriteFailed
    case previewChanged
    case svgExtractionFailed(Error)
    case svgNotFound
    case noDiagram

    static func == (lhs: ExportError, rhs: ExportError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidPNGData, .invalidPNGData),
            (.pasteboardWriteFailed, .pasteboardWriteFailed),
            (.previewChanged, .previewChanged),
            (.svgNotFound, .svgNotFound),
            (.noDiagram, .noDiagram):
            true
        case (.rasterizationFailed(let l), .rasterizationFailed(let r)):
            l == r
        case (.svgExtractionFailed(let l), .svgExtractionFailed(let r)):
            l.localizedDescription == r.localizedDescription
        default:
            false
        }
    }

    var errorDescription: String? {
        switch self {
        case .rasterizationFailed(let message):
            "Failed to render diagram as PNG: \(message)"
        case .invalidPNGData:
            "Failed to decode rendered PNG data"
        case .pasteboardWriteFailed:
            "Failed to copy the diagram to the pasteboard"
        case .previewChanged:
            "The preview changed before export completed"
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

    func copyAsPNG(padding: CGFloat = 16, background: ExportBackground = .transparent) async -> Result<Data, ExportError> {
        let js = """
            if (typeof window.rasterizeExportSVG !== 'function') {
                return { success: false, error: 'PNG export runtime is unavailable' };
            }
            return await window.rasterizeExportSVG(padding, fillBackground);
            """

        do {
            let result = try await webView.callAsyncJavaScript(
                js,
                arguments: ["padding": max(0, padding), "fillBackground": background == .theme],
                contentWorld: .page
            )
            guard let response = result as? [String: Any],
                let success = response["success"] as? Bool
            else {
                return .failure(.rasterizationFailed("Unexpected preview response"))
            }
            guard success else {
                if response["noDiagram"] as? Bool == true {
                    return .failure(.noDiagram)
                }
                let message = response["error"] as? String ?? "Unknown rasterization error"
                logger.error("PNG export failed: \(message, privacy: .public)")
                return .failure(.rasterizationFailed(message))
            }
            guard let encodedData = response["data"] as? String,
                let pngData = Data(base64Encoded: encodedData),
                !pngData.isEmpty
            else {
                logger.error("PNG export failed: preview returned invalid image data")
                return .failure(.invalidPNGData)
            }
            logger.info("PNG export succeeded")
            return .success(pngData)
        } catch {
            logger.error("PNG rasterization failed: \(error.localizedDescription)")
            return .failure(.rasterizationFailed(error.localizedDescription))
        }
    }

    func copySVG(background: ExportBackground = .transparent) async -> Result<String, ExportError> {
        let js = """
            return typeof window.getExportSVG === 'function' ? window.getExportSVG(fillBackground) : '';
            """
        do {
            let result = try await webView.callAsyncJavaScript(
                js,
                arguments: ["fillBackground": background == .theme],
                contentWorld: .page
            )
            guard let rawSvg = result as? String else {
                logger.error("SVG extraction failed: unexpected type \(type(of: result))")
                return .failure(
                    .svgExtractionFailed(
                        NSError(
                            domain: "DiagramExporter", code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "Unexpected result type"])))
            }
            guard !rawSvg.isEmpty else {
                logger.error("SVG extraction failed: no SVG element found")
                return .failure(.svgNotFound)
            }

            let sanitizedSvg = try SVGSanitizer.sanitize(rawSvg)

            logger.info("SVG export succeeded")
            return .success(sanitizedSvg)
        } catch {
            logger.error("SVG extraction failed: \(error.localizedDescription)")
            return .failure(.svgExtractionFailed(error))
        }
    }

}
