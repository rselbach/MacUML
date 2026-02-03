import Testing
@testable import MacUML

@Suite("PlantUML Renderer Tests")
struct PlantUMLRendererTests {

    @Test("Render state starts idle")
    @MainActor
    func initialState() async {
        let renderer = PlantUMLRenderer()
        #expect(renderer.state == .idle)
    }

    @Test("Empty source stays idle")
    @MainActor
    func emptySource() async throws {
        let renderer = PlantUMLRenderer()
        renderer.render(source: "   ")

        // Wait for debounce
        try await Task.sleep(for: .milliseconds(400))

        #expect(renderer.state == .idle)
    }
}
