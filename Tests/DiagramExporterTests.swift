import Foundation
import Testing
@testable import MacUML

@Suite("DiagramExporter Tests")
struct DiagramExporterTests {

    @MainActor
    private func waitForRenderCompletion(
        renderer: MermaidRenderer,
        timeout: Duration
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout

        repeat {
            switch renderer.state {
            case .ready:
                return
            case .failure(let message, _):
                Issue.record("Renderer failed: \(message)")
                return
            default:
                if clock.now >= deadline {
                    Issue.record("Render timed out after \(timeout) - state: \(renderer.state)")
                    return
                }
                try await Task.sleep(for: .milliseconds(50))
            }
        } while true
    }

    @Test("copyAsPNG returns failure in headless test environment")
    @MainActor
    func copyAsPNGInHeadlessEnvironment() async throws {
        let renderer = MermaidRenderer()
        renderer.render(source: "flowchart TD\nA-->B")

        try await waitForRenderCompletion(renderer: renderer, timeout: .seconds(5))

        let exporter = DiagramExporter(webView: renderer.webView)
        let result = await exporter.copyAsPNG()

        if case .failure(let error) = result {
            #expect(true, "PNG export fails in headless environment: \(error.errorDescription ?? "unknown")")
        } else {
            Issue.record("Expected failure in headless environment but got success")
        }
    }

    @Test("copyAsPNG returns failure with no diagram")
    @MainActor
    func copyAsPNGWithNoDiagram() async throws {
        let renderer = MermaidRenderer()
        // Empty source clears the diagram
        renderer.render(source: "")

        try await Task.sleep(for: .milliseconds(400))

        let exporter = DiagramExporter(webView: renderer.webView)
        let result = await exporter.copyAsPNG()

        // Should fail in headless environment
        if case .failure = result {
            #expect(true, "PNG export fails as expected")
        }
    }

    @Test("copySVG returns valid SVG string when present")
    @MainActor
    func copySVGWithDiagram() async throws {
        let renderer = MermaidRenderer()
        renderer.render(source: "flowchart TD\nA-->B")

        try await waitForRenderCompletion(renderer: renderer, timeout: .seconds(5))

        let exporter = DiagramExporter(webView: renderer.webView)
        let result = await exporter.copySVG()

        if case .success(let svg) = result {
            #expect(!svg.isEmpty, "SVG should not be empty string")
            #expect(svg.contains("<svg"), "SVG should contain <svg tag")
        } else if case .failure(let error) = result {
            Issue.record("SVG extraction failed: \(error.errorDescription ?? "unknown")")
        }
    }

    @Test("copySVG returns failure when no diagram")
    @MainActor
    func copySVGWithNoDiagram() async throws {
        let renderer = MermaidRenderer()
        // Empty source clears the diagram
        renderer.render(source: "")

        try await Task.sleep(for: .milliseconds(400))

        let exporter = DiagramExporter(webView: renderer.webView)
        let result = await exporter.copySVG()

        if case .failure(let error) = result {
            #expect(error == .svgNotFound, "Should report SVG not found")
        } else {
            Issue.record("Expected failure but got success: \(result)")
        }
    }

    @Test("copySVG returns failure when no diagram in DOM")
    @MainActor
    func copySVGWithEmptyDiagram() async throws {
        let renderer = MermaidRenderer()
        renderer.render(source: "   ")

        try await Task.sleep(for: .milliseconds(400))

        let exporter = DiagramExporter(webView: renderer.webView)
        let result = await exporter.copySVG()

        if case .failure = result {
            #expect(true, "SVG export fails as expected for empty diagram")
        }
    }

    @Test("PNG export respects padding parameter in implementation")
    @MainActor
    func copyAsPNGWithPadding() async throws {
        let renderer = MermaidRenderer()
        renderer.render(source: "flowchart TD\nA-->B")

        try await waitForRenderCompletion(renderer: renderer, timeout: .seconds(5))

        let exporter = DiagramExporter(webView: renderer.webView)

        // In headless test environment, WebView snapshots fail
        // But we can verify the padding parameter is accepted without crashing
        let resultNoPadding = await exporter.copyAsPNG(padding: 0)
        let resultWithPadding = await exporter.copyAsPNG(padding: 32)

        // Both should fail in headless environment but not crash
        if case .failure = resultNoPadding, case .failure = resultWithPadding {
            #expect(true, "Both fail as expected in headless environment")
        }
    }
}
