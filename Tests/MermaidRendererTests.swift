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
}
