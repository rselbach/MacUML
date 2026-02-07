import Foundation
import WebKit

extension MermaidRenderer {
    internal func schedulePreviewRuntimeValidation() {
        guard previewRuntimeValidationTask == nil else {
            return
        }

        previewRuntimeValidationTask = Task { @MainActor in
            await validatePreviewRuntime()
            previewRuntimeValidationTask = nil
        }
    }

    private func validatePreviewRuntime() async {
        let hasSource = !lastSource.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
        for _ in 0..<20 {
            do {
                guard let result = try await webView.evaluateJavaScript(js) as? [String: Any] else {
                    try await Task.sleep(for: .milliseconds(100))
                    continue
                }

                let hasMermaid = result["hasMermaid"] as? Bool ?? false
                let hasRenderDiagram = result["hasRenderDiagram"] as? Bool ?? false
                let hasSetTheme = result["hasSetTheme"] as? Bool ?? false
                let hasSetZoom = result["hasSetZoom"] as? Bool ?? false
                lastFlags = (hasMermaid, hasRenderDiagram, hasSetTheme, hasSetZoom)

                if hasMermaid && hasRenderDiagram && hasSetTheme && hasSetZoom {
                    if !mermaidReady {
                        logger.info("Preview runtime validated before ready callback; enabling fallback readiness")
                        handleMermaidReady()
                    }
                    return
                }
            } catch {
                logger.error("Preview runtime validation attempt failed: \(error.localizedDescription, privacy: .public)")
            }

            do {
                try await Task.sleep(for: .milliseconds(100))
            } catch {
                return
            }
        }

        if let lastFlags {
            logger.error(
                "Preview runtime invalid: hasMermaid=\(lastFlags.hasMermaid, privacy: .public), hasRenderDiagram=\(lastFlags.hasRenderDiagram, privacy: .public), hasSetTheme=\(lastFlags.hasSetTheme, privacy: .public), hasSetZoom=\(lastFlags.hasSetZoom, privacy: .public)"
            )
            if hasSource {
                state = .failure("Preview runtime failed (mermaid:\(lastFlags.hasMermaid), render:\(lastFlags.hasRenderDiagram), theme:\(lastFlags.hasSetTheme), zoom:\(lastFlags.hasSetZoom))")
            }
            return
        }

        logger.error("Preview runtime validation returned no usable result")
        if hasSource {
            state = .failure("Preview runtime did not initialize")
        }
    }

    internal func auditPreviewDOM(context: String) async {
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
                        logger.error("Preview DOM audit (\(context, privacy: .public)) failed to decode extras payload as UTF-8")
                    }
                } catch {
                    logger.error("Preview DOM audit (\(context, privacy: .public)) failed to serialize extras payload: \(error.localizedDescription, privacy: .public)")
                }
            }

            logger.error(
                "Preview DOM audit (\(context, privacy: .public)): extra nodes=\(extraNodeCount, privacy: .public), details=\(details, privacy: .public)"
            )
        } catch {
            logger.error("Preview DOM audit failed (\(context, privacy: .public)): \(error.localizedDescription, privacy: .public)")
        }
    }

    internal func fetchDiagramMetrics() async -> (hasSVG: Bool, width: Double, height: Double)? {
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
            return (hasSVG, width, height)
        } catch {
            logger.error("Failed to fetch diagram metrics: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
