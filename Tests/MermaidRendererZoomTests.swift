import Foundation
import Testing

@testable import MacUML

@Suite("Mermaid Renderer Zoom Tests", .serialized)
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

    @Test("Wheel scrolling pans both axes without changing zoom")
    @MainActor
    func wheelScrollingPans() async throws {
        let renderer = try await makeRenderedRenderer()

        let result =
            try await renderer.webView.evaluateJavaScript(
                """
                (function() {
                    const container = document.getElementById('diagram');
                    window.setZoom(2);
                    window.setPan(0, 0);
                    container.dispatchEvent(new WheelEvent('wheel', {
                        deltaX: 2,
                        deltaY: 3,
                        deltaMode: WheelEvent.DOM_DELTA_LINE,
                        bubbles: true,
                        cancelable: true
                    }));
                    return { zoom: window.zoomLevel, panX: window.panX, panY: window.panY };
                })()
                """
            ) as? [String: Any]

        #expect(number(result, key: "zoom") == 2)
        #expect(number(result, key: "panX") == -32)
        #expect(number(result, key: "panY") == -48)
    }

    @Test("Option, Command, and Control wheel zoom around the pointer")
    @MainActor
    func modifiedWheelZoomsAroundPointer() async throws {
        let renderer = try await makeRenderedRenderer()

        let result =
            try await renderer.webView.evaluateJavaScript(
                """
                (function() {
                    const container = document.getElementById('diagram');
                    const rect = container.getBoundingClientRect();
                    const eventOptions = {
                        deltaY: -50,
                        clientX: rect.left + (rect.width * 0.75),
                        clientY: rect.top + (rect.height * 0.25),
                        bubbles: true,
                        cancelable: true
                    };
                    function dispatchWithModifier(modifier) {
                        window.setZoom(1.5);
                        window.setPan(0, 0);
                        container.dispatchEvent(new WheelEvent('wheel', {
                            ...eventOptions,
                            [modifier]: true
                        }));
                        return { zoom: window.zoomLevel, panX: window.panX, panY: window.panY };
                    }
                    return {
                        option: dispatchWithModifier('altKey'),
                        command: dispatchWithModifier('metaKey'),
                        control: dispatchWithModifier('ctrlKey')
                    };
                })()
                """
            ) as? [String: Any]

        let option = result?["option"] as? [String: Any]
        let command = result?["command"] as? [String: Any]
        let control = result?["control"] as? [String: Any]
        #expect(number(option, key: "zoom") ?? 0 > 1.5)
        #expect(number(command, key: "zoom") ?? 0 > 1.5)
        #expect(number(control, key: "zoom") ?? 0 > 1.5)
        #expect(number(option, key: "panX") ?? 0 < 0)
        #expect(number(option, key: "panY") ?? 0 > 0)
    }

    @Test("Pinch gesture continues to zoom")
    @MainActor
    func pinchGestureZooms() async throws {
        let renderer = try await makeRenderedRenderer()

        let result =
            try await renderer.webView.evaluateJavaScript(
                """
                (function() {
                    function gestureEvent(type, scale) {
                        const event = new Event(type, { bubbles: true, cancelable: true });
                        Object.defineProperties(event, {
                            scale: { value: scale },
                            clientX: { value: 400 },
                            clientY: { value: 300 }
                        });
                        return event;
                    }
                    window.setZoom(1.2);
                    document.dispatchEvent(gestureEvent('gesturestart', 1));
                    document.dispatchEvent(gestureEvent('gesturechange', 1.5));
                    return window.zoomLevel;
                })()
                """
            ) as? NSNumber

        #expect(abs((result?.doubleValue ?? 0) - 1.8) < 0.000_001)
    }

    @Test("Reset zoom clears pan")
    @MainActor
    func resetZoomClearsPan() async throws {
        let renderer = try await makeRenderedRenderer()

        let result =
            try await renderer.webView.evaluateJavaScript(
                """
                (function() {
                    window.setZoom(2);
                    window.setPan(80, -60);
                    window.resetZoom();
                    return { zoom: window.zoomLevel, panX: window.panX, panY: window.panY };
                })()
                """
            ) as? [String: Any]

        #expect(number(result, key: "zoom") == 1)
        #expect(number(result, key: "panX") == 0)
        #expect(number(result, key: "panY") == 0)
    }
}

@MainActor
private func makeRenderedRenderer() async throws -> MermaidRenderer {
    let renderer = MermaidRenderer()
    renderer.webView.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
    renderer.render(source: "flowchart LR\nTroy[Troy Barnes] --> Abed[Abed Nadir]")

    let clock = ContinuousClock()
    let deadline = clock.now + .seconds(5)
    while renderer.state != .ready {
        if case .failure(let error) = renderer.state {
            Issue.record("Renderer failed: \(error.message)")
            return renderer
        }
        if clock.now >= deadline {
            Issue.record("Render timed out: \(renderer.state)")
            return renderer
        }
        try await Task.sleep(for: .milliseconds(50))
    }
    return renderer
}

private func number(_ values: [String: Any]?, key: String) -> Double? {
    (values?[key] as? NSNumber)?.doubleValue
}
