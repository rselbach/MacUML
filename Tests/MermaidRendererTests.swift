import Testing
@testable import MacUML

@Suite("Mermaid Renderer Tests")
struct MermaidRendererTests {

    @Test("Render state starts idle")
    @MainActor
    func initialState() async {
        let renderer = MermaidRenderer()
        #expect(renderer.state == .idle)
    }

    @Test("Empty source stays idle")
    @MainActor
    func emptySource() async throws {
        let renderer = MermaidRenderer()
        renderer.render(source: "   ")

        try await Task.sleep(for: .milliseconds(400))

        #expect(renderer.state == .idle)
    }

    @Test("Simple diagram renders to SVG")
    @MainActor
    func rendersSimpleDiagram() async throws {
        let renderer = MermaidRenderer()
        renderer.render(source: "flowchart TD\nA-->B")

        try await waitForRenderCompletion(renderer: renderer, timeout: .seconds(5))

        let js = "document.querySelector('#diagram svg')?.outerHTML ?? ''"
        let svgHTML = try await renderer.webView.evaluateJavaScript(js) as? String
        #expect(svgHTML?.isEmpty == false)
    }

    @Test("Simple diagram renders to SVG after delayed render call")
    @MainActor
    func rendersSimpleDiagramAfterDelay() async throws {
        let renderer = MermaidRenderer()
        try await Task.sleep(for: .milliseconds(400))
        renderer.render(source: "flowchart TD\nA-->B")

        try await waitForRenderCompletion(renderer: renderer, timeout: .seconds(5))

        let js = "document.querySelector('#diagram svg')?.outerHTML ?? ''"
        let svgHTML = try await renderer.webView.evaluateJavaScript(js) as? String
        #expect(svgHTML?.isEmpty == false)
    }

    @Test("Malformed render response fails")
    @MainActor
    func malformedRenderResponseFails() async throws {
        let renderer = MermaidRenderer()
        try await waitForRuntimeReady(renderer: renderer, timeout: .seconds(5))

        _ = try await renderer.webView.evaluateJavaScript(
            "window.renderDiagram = async function() { return null; }; true;"
        )

        await renderer.performRender(source: "flowchart TD\nA-->B")

        guard case .failure(let error) = renderer.state else {
            Issue.record("Expected malformed response to fail, got \(renderer.state)")
            return
        }
        #expect(error.message == "Preview runtime returned an unexpected render response.")
    }
}

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
        case .failure(let error):
            Issue.record("Renderer failed: \(error.message)")
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

@MainActor
private func waitForRuntimeReady(
    renderer: MermaidRenderer,
    timeout: Duration
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout

    repeat {
        if renderer.mermaidReady {
            return
        }

        if clock.now >= deadline {
            Issue.record("Runtime did not become ready after \(timeout)")
            return
        }

        try await Task.sleep(for: .milliseconds(50))
    } while true
}
