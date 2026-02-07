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

        // Wait for debounce
        try await Task.sleep(for: .milliseconds(400))

        #expect(renderer.state == .idle)
    }

    @Test("Simple diagram renders to SVG")
    @MainActor
    func rendersSimpleDiagram() async throws {
        let renderer = MermaidRenderer()
        renderer.render(source: "flowchart TD\nA-->B")

        for _ in 0..<30 {
            if case .ready = renderer.state {
                break
            }
            if case .failure = renderer.state {
                break
            }
            try await Task.sleep(for: .milliseconds(200))
        }

        if case .failure(let message) = renderer.state {
            Issue.record("Renderer failed: \(message)")
        }

        #expect(renderer.state == .ready)

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

        for _ in 0..<30 {
            if case .ready = renderer.state {
                break
            }
            if case .failure = renderer.state {
                break
            }
            try await Task.sleep(for: .milliseconds(200))
        }

        if case .failure(let message) = renderer.state {
            Issue.record("Renderer failed after delayed render: \(message)")
        }

        #expect(renderer.state == .ready)

        let js = "document.querySelector('#diagram svg')?.outerHTML ?? ''"
        let svgHTML = try await renderer.webView.evaluateJavaScript(js) as? String
        #expect(svgHTML?.isEmpty == false)
    }
}
