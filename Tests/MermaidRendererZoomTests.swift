import Testing
@testable import MacUML

@Suite("Mermaid Renderer Zoom Tests")
struct MermaidRendererZoomTests {

    @Test("Initial zoom level is 1.0")
    @MainActor
    func initialZoomLevel() async {
        let renderer = MermaidRenderer()
        #expect(renderer.zoomLevel == 1.0)
    }

    @Test("zoomIn increases zoom by 0.1")
    @MainActor
    func zoomInIncreasesZoom() async {
        let renderer = MermaidRenderer()
        renderer.zoomIn()
        #expect(renderer.zoomLevel == 1.1)
    }

    @Test("zoomOut decreases zoom by 0.1")
    @MainActor
    func zoomOutDecreasesZoom() async {
        let renderer = MermaidRenderer()
        renderer.zoomOut()
        #expect(renderer.zoomLevel == 0.9)
    }

    @Test("zoom is clamped to maximum 5.0")
    @MainActor
    func zoomClampedToMax() async {
        let renderer = MermaidRenderer()
        renderer.setZoom(4.95)
        renderer.zoomIn()
        #expect(renderer.zoomLevel == 5.0)
    }

    @Test("zoom is clamped to minimum 0.25")
    @MainActor
    func zoomClampedToMin() async {
        let renderer = MermaidRenderer()
        renderer.setZoom(0.3)
        renderer.zoomOut()
        #expect(renderer.zoomLevel == 0.25)
    }

    @Test("resetZoom returns to 1.0")
    @MainActor
    func resetZoomReturnsToDefault() async {
        let renderer = MermaidRenderer()
        renderer.zoomIn()
        renderer.zoomIn()
        #expect(renderer.zoomLevel == 1.2)
        renderer.resetZoom()
        #expect(renderer.zoomLevel == 1.0)
    }
}
