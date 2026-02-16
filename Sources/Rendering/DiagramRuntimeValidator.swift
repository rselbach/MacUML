import Foundation
import WebKit
import os

/// Metrics describing the current diagram state in the WebView.
struct DiagramMetrics: Equatable {
    /// Whether an SVG element exists in the diagram container.
    let hasSVG: Bool
    /// Width of the SVG element in points.
    let width: Double
    /// Height of the SVG element in points.
    let height: Double
}

/// Validates that the Mermaid.js runtime is properly initialized in the WebView.
///
/// Performs exponential backoff validation to detect when:
/// - Mermaid.js library is loaded
/// - renderDiagram function is available
/// - Theme and zoom setters are ready
///
/// Reports failures to the renderer for user-facing error display.
@MainActor
class DiagramRuntimeValidator {
    weak var webView: DiagramWebView?
    var trustedPreviewFiles: Set<URL> = []
    var validationTask: Task<Void, Never>?

    private let logger = Logger(subsystem: "com.macuml", category: "DiagramRuntimeValidator")
    private let validationMaxAttempts: Int = 20
    private let validationInitialDelay: Duration = .milliseconds(50)
    private let validationMaxDelay: Duration = .milliseconds(500)

    private var onReady: (@MainActor () -> Void)?
    private var onFailure: (@MainActor (String) -> Void)?
    private var hasSource: () -> Bool = { false }

    init(webView: DiagramWebView) {
        self.webView = webView
    }

    func configure(
        hasSource: @escaping @MainActor () -> Bool,
        onReady: @escaping @MainActor () -> Void,
        onFailure: @escaping @MainActor (String) -> Void
    ) {
        self.hasSource = hasSource
        self.onReady = onReady
        self.onFailure = onFailure
    }

    func scheduleValidation() {
        guard validationTask == nil else { return }

        validationTask = Task { @MainActor [weak self] in
            await self?.validateRuntime()
            self?.validationTask = nil
        }
    }

    func cancelValidation() {
        validationTask?.cancel()
        validationTask = nil
    }

    private func validateRuntime() async {
        guard let webView else { return }

        let js = """
            (function() {
                return {
                    hasMermaid: typeof mermaid !== 'undefined',
                    hasRenderDiagram: typeof window.renderDiagram === 'function',
                    hasSetTheme: typeof window.setTheme === 'function',
                    hasSetZoom: typeof window.setZoom === 'function'
                };
            })()
            """

        var lastFlags: (hasMermaid: Bool, hasRenderDiagram: Bool, hasSetTheme: Bool, hasSetZoom: Bool)?
        var delay = validationInitialDelay

        for _ in 0..<validationMaxAttempts {
            do {
                guard let result = try await webView.evaluateJavaScript(js) as? [String: Any] else {
                    try await Task.sleep(for: delay)
                    delay = min(delay * 2, validationMaxDelay)
                    continue
                }

                let hasMermaid = result["hasMermaid"] as? Bool ?? false
                let hasRenderDiagram = result["hasRenderDiagram"] as? Bool ?? false
                let hasSetTheme = result["hasSetTheme"] as? Bool ?? false
                let hasSetZoom = result["hasSetZoom"] as? Bool ?? false
                lastFlags = (hasMermaid, hasRenderDiagram, hasSetTheme, hasSetZoom)

                if hasMermaid && hasRenderDiagram && hasSetTheme && hasSetZoom {
                    logger.info("Runtime validated successfully")
                    onReady?()
                    return
                }
            } catch {
                logger.error("Validation attempt failed: \(error.localizedDescription, privacy: .public)")
            }

            do {
                try await Task.sleep(for: delay)
                delay = min(delay * 2, validationMaxDelay)
            } catch {
                return
            }
        }

        if let lastFlags {
            logger.error(
                "Runtime invalid: hasMermaid=\(lastFlags.hasMermaid, privacy: .public), hasRenderDiagram=\(lastFlags.hasRenderDiagram, privacy: .public), hasSetTheme=\(lastFlags.hasSetTheme, privacy: .public), hasSetZoom=\(lastFlags.hasSetZoom, privacy: .public)"
            )
            if hasSource() {
                let message = "Preview runtime failed (mermaid:\(lastFlags.hasMermaid), render:\(lastFlags.hasRenderDiagram), theme:\(lastFlags.hasSetTheme), zoom:\(lastFlags.hasSetZoom))"
                onFailure?(message)
            }
            return
        }

        logger.error("Runtime validation returned no usable result")
        if hasSource() {
            onFailure?("Preview runtime did not initialize")
        }
    }

    func auditDOM(context: String) async {
        guard let webView else { return }

        let js = """
            if (typeof window.collectPreviewDiagnostics !== 'function') {
                return null;
            }
            return window.collectPreviewDiagnostics();
            """

        do {
            guard let result = try await webView.evaluateJavaScript(js) as? [String: Any],
                  let extraNodeCount = result["extraNodeCount"] as? Int,
                  extraNodeCount > 0 else {
                return
            }

            var details = "[]"
            if let extras = result["extras"] as? [[String: Any]] {
                do {
                    let data = try JSONSerialization.data(withJSONObject: extras, options: [])
                    if let text = String(data: data, encoding: .utf8) {
                        details = text
                    } else {
                        logger.error("DOM audit (\(context, privacy: .public)) failed to decode extras payload as UTF-8")
                    }
                } catch {
                    logger.error("DOM audit (\(context, privacy: .public)) failed to serialize extras payload: \(error.localizedDescription, privacy: .public)")
                }
            }

            logger.error(
                "DOM audit (\(context, privacy: .public)): extra nodes=\(extraNodeCount, privacy: .public), details=\(details, privacy: .public)"
            )
        } catch {
            logger.error("DOM audit failed (\(context, privacy: .public)): \(error.localizedDescription, privacy: .public)")
        }
    }

    func fetchMetrics() async -> DiagramMetrics? {
        guard let webView else { return nil }

        let js = """
            (function() {
                const svg = document.querySelector('#diagram svg');
                if (!svg) {
                    return { hasSVG: false, width: 0, height: 0 };
                }
                const rect = svg.getBoundingClientRect();
                return { hasSVG: true, width: rect.width, height: rect.height };
            })()
            """

        do {
            guard let result = try await webView.evaluateJavaScript(js) as? [String: Any],
                  let hasSVG = result["hasSVG"] as? Bool,
                  let width = result["width"] as? Double,
                  let height = result["height"] as? Double else {
                return nil
            }
            return DiagramMetrics(hasSVG: hasSVG, width: width, height: height)
        } catch {
            logger.error("Failed to fetch diagram metrics: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}