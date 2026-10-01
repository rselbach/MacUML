import Foundation
import Testing

@testable import MacUML

@Suite("Mermaid Renderer Tests", .serialized)
struct MermaidRendererTests {

    @Test("Render state starts idle")
    @MainActor
    func initialState() async {
        let renderer = MermaidRenderer()
        #expect(renderer.state == .idle)
        #expect(!renderer.hasDiagram)
        #expect(!renderer.isPreviewStale)
        #expect(!renderer.canExport)
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
        #expect(renderer.hasDiagram)
        #expect(!renderer.isPreviewStale)
        #expect(renderer.canExport)
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

        renderer.render(source: "flowchart TD\nA-->B", force: true)
        try await waitForState(renderer: renderer, timeout: .seconds(5)) {
            if case .failure = $0.state { return true }
            return false
        }

        guard case .failure(let error) = renderer.state else {
            Issue.record("Expected malformed response to fail, got \(renderer.state)")
            return
        }
        #expect(error.message == "Preview runtime returned an unexpected render response.")
    }

    @Test("Labels containing Mermaid error phrases render")
    @MainActor
    func errorPhraseLabelsRender() async throws {
        let renderer = MermaidRenderer()
        renderer.render(source: "flowchart TD\nA[\"Syntax error\"] --> B[\"Parse error\"]")

        try await waitForRenderCompletion(renderer: renderer, timeout: .seconds(5))

        let text =
            try await renderer.webView.evaluateJavaScript(
                "document.querySelector('#diagram svg')?.textContent ?? ''"
            ) as? String
        #expect(text?.contains("Syntax error") == true)
        #expect(text?.contains("Parse error") == true)
    }

    @Test("Error line includes leading CRLF blank lines and Unicode source")
    @MainActor
    func leadingBlankLineErrorMapping() async throws {
        let renderer = MermaidRenderer()
        renderer.render(source: "\r\n\r\nflowchart TD\r\nA[\"Troy 🐒\"] -->")

        try await waitForState(renderer: renderer, timeout: .seconds(5)) {
            if case .failure = $0.state { return true }
            return false
        }

        guard case .failure(let error) = renderer.state else {
            Issue.record("Expected malformed source to fail, got \(renderer.state)")
            return
        }
        #expect(error.line == 4)
    }

    @Test(
        "Error lines account for text Mermaid strips before parsing",
        arguments: [
            ("---\ntitle: Troy\n---\nflowchart TD\n    A-->B\n    C[[[ bad\n    D-->E\n", 6),
            ("---\nconfig:\n  theme: forest\n---\n\n\nflowchart TD\n    C[[[ bad\n", 8),
            ("%%{init: {'theme':'forest'}}%%\nflowchart TD\n    A-->B\n    C[[[ bad\n", 4),
            ("%%{\n  init: {'theme':'forest'}\n}%%\nflowchart TD\n    C[[[ bad\n", 5),
            ("%% Greendale\nflowchart TD\n    A-->B\n    C[[[ bad\n", 4),
            ("flowchart TD\n    %% Troy\n\n    %% Abed\n    A-->B\n    C[[[ bad\n", 6),
            ("\n\nflowchart TD\n    A-->B\n    C[[[ bad\n", 5),
            ("flowchart TD\n    A-->B\n    C[[[ bad\n", 3),
            ("\nflowchart TD\n    Troy -->\n\n\n", 3),
        ])
    @MainActor
    func errorLinesMapToOriginalSource(source: String, line: Int) async throws {
        let renderer = MermaidRenderer()
        renderer.render(source: source)

        try await waitForState(renderer: renderer, timeout: .seconds(5)) {
            if case .failure = $0.state { return true }
            return false
        }

        #expect(renderer.state.error?.line == line, "\(renderer.state.error?.message ?? "no error")")
    }

    @Test("Clearing source invalidates pending work and prevents theme restoration")
    @MainActor
    func clearInvalidatesRenderedSource() async throws {
        let renderer = MermaidRenderer()
        renderer.render(source: "flowchart TD\nA[\"Troy\"] --> B[\"Abed\"]")
        try await waitForRenderCompletion(renderer: renderer, timeout: .seconds(5))

        renderer.render(source: "")
        try await waitForState(renderer: renderer, timeout: .seconds(5)) { $0.state == .idle }
        renderer.theme = .dark
        try await Task.sleep(for: .milliseconds(400))

        let hasSVG =
            try await renderer.webView.evaluateJavaScript(
                "document.querySelector('#diagram svg') !== null"
            ) as? Bool
        #expect(hasSVG == false)
        #expect(!renderer.hasDiagram)
        #expect(!renderer.canExport)

        renderer.render(source: "flowchart TD\nA -->")
        try await waitForState(renderer: renderer, timeout: .seconds(5)) {
            if case .failure = $0.state { return true }
            return false
        }
        guard case .failure = renderer.state else {
            Issue.record("Expected invalid replacement source to fail")
            return
        }

        let hasRestoredSVG =
            try await renderer.webView.evaluateJavaScript(
                "document.querySelector('#diagram svg') !== null"
            ) as? Bool
        #expect(hasRestoredSVG == false)
    }

    @Test("Failed current source marks the last successful diagram stale")
    @MainActor
    func failedSourceMarksPreviewStale() async throws {
        let renderer = MermaidRenderer()
        renderer.render(source: "flowchart TD\nA --> B")
        try await waitForRenderCompletion(renderer: renderer, timeout: .seconds(5))

        renderer.render(source: "flowchart TD\nA -->")
        #expect(renderer.hasDiagram)
        #expect(renderer.isPreviewStale)
        #expect(!renderer.canExport)
        try await waitForState(renderer: renderer, timeout: .seconds(5)) {
            if case .failure = $0.state { return true }
            return false
        }

        #expect(renderer.hasDiagram)
        #expect(renderer.isPreviewStale)
        #expect(!renderer.canExport)
    }

    @Test("Theme changes rerender the current native source")
    @MainActor
    func themeChangeRendersCurrentSource() async throws {
        let renderer = MermaidRenderer()
        renderer.render(source: "flowchart TD\nA[\"Troy\"] --> B[\"Abed\"]")
        try await waitForRenderCompletion(renderer: renderer, timeout: .seconds(5))

        renderer.theme = .forest
        #expect(renderer.isPreviewStale)
        #expect(!renderer.canExport)
        try await waitForRenderCompletion(renderer: renderer, timeout: .seconds(5))

        let values =
            try await renderer.webView.evaluateJavaScript(
                "({ text: document.querySelector('#diagram svg')?.textContent ?? '', theme: window.currentTheme })"
            ) as? [String: Any]
        #expect((values?["text"] as? String)?.contains("Troy") == true)
        #expect(values?["theme"] as? String == "forest")
        #expect(renderer.canExport)
    }

    @Test("Paused live preview tracks edits until refresh or resume")
    @MainActor
    func pausedLivePreviewTracksEdits() async throws {
        let renderer = MermaidRenderer()
        renderer.render(source: "flowchart TD\nA[\"Troy\"] --> B[\"Abed\"]")
        try await waitForRenderCompletion(renderer: renderer, timeout: .seconds(5))

        renderer.isLivePreviewEnabled = false
        renderer.render(source: "flowchart TD\nA[\"Shirley\"] --> B[\"Annie\"]")
        try await Task.sleep(for: .milliseconds(400))

        let pausedText =
            try await renderer.webView.evaluateJavaScript(
                "document.querySelector('#diagram svg')?.textContent ?? ''"
            ) as? String
        #expect(pausedText?.contains("Troy") == true)
        #expect(pausedText?.contains("Shirley") == false)
        #expect(renderer.state == .ready)
        #expect(renderer.isPreviewStale)
        #expect(!renderer.canExport)

        renderer.refreshCurrentSource()
        try await waitForRenderCompletion(renderer: renderer, timeout: .seconds(5))
        let refreshedText =
            try await renderer.webView.evaluateJavaScript(
                "document.querySelector('#diagram svg')?.textContent ?? ''"
            ) as? String
        #expect(refreshedText?.contains("Shirley") == true)
        #expect(renderer.canExport)

        renderer.render(source: "flowchart TD\nA[\"Pierce\"] --> B[\"Britta\"]")
        #expect(renderer.isPreviewStale)
        renderer.isLivePreviewEnabled = true
        try await waitForRenderCompletion(renderer: renderer, timeout: .seconds(5))
        let resumedText =
            try await renderer.webView.evaluateJavaScript(
                "document.querySelector('#diagram svg')?.textContent ?? ''"
            ) as? String
        #expect(resumedText?.contains("Pierce") == true)
        #expect(renderer.canExport)
    }

    @Test("Paused live preview still clears empty source")
    @MainActor
    func pausedLivePreviewClearsEmptySource() async throws {
        let renderer = MermaidRenderer()
        renderer.render(source: "flowchart TD\nA --> B")
        try await waitForRenderCompletion(renderer: renderer, timeout: .seconds(5))

        renderer.isLivePreviewEnabled = false
        renderer.render(source: "")
        try await waitForState(renderer: renderer, timeout: .seconds(5)) { !$0.hasDiagram }

        let hasSVG =
            try await renderer.webView.evaluateJavaScript(
                "document.querySelector('#diagram svg') !== null"
            ) as? Bool
        #expect(hasSVG == false)
        #expect(renderer.state == .idle)
        #expect(!renderer.canExport)
    }

    @Test("Manual refresh reloads an unavailable runtime")
    @MainActor
    func refreshReloadsUnavailableRuntime() async throws {
        let renderer = MermaidRenderer()
        renderer.render(source: "flowchart TD\nTroy --> Abed")
        try await waitForRenderCompletion(renderer: renderer, timeout: .seconds(5))
        _ = try await renderer.webView.evaluateJavaScript("window.renderDiagram = undefined;")
        renderer.mermaidReady = false
        renderer.state = .failure(error: MermaidError(message: "Preview runtime did not initialize", line: nil))

        renderer.refreshCurrentSource()
        try await waitForRenderCompletion(renderer: renderer, timeout: .seconds(8))

        #expect(renderer.canExport)
        let text = try await renderer.webView.evaluateJavaScript("document.querySelector('#diagram svg').textContent")
        #expect((text as? String)?.contains("Troy") == true)
        #expect((text as? String)?.contains("Abed") == true)
    }

    @Test("Web content process recovery restores source theme and zoom")
    @MainActor
    func processRecoveryRestoresRenderer() async throws {
        let renderer = MermaidRenderer()
        renderer.theme = .forest
        renderer.setZoom(1.4)
        renderer.render(source: "flowchart TD\nA[\"Greendale\"] --> B[\"Study Room\"]")
        try await waitForRenderCompletion(renderer: renderer, timeout: .seconds(5))

        renderer.webViewWebContentProcessDidTerminate(renderer.webView)
        await Task.yield()
        try await waitForState(renderer: renderer, timeout: .seconds(5)) { !$0.mermaidReady }
        #expect(!renderer.hasDiagram)
        #expect(!renderer.canExport)
        try await waitForRenderCompletion(renderer: renderer, timeout: .seconds(8))

        let values =
            try await renderer.webView.evaluateJavaScript(
                "({ text: document.querySelector('#diagram svg')?.textContent ?? '', theme: window.currentTheme, zoom: window.zoomLevel })"
            ) as? [String: Any]
        #expect((values?["text"] as? String)?.contains("Greendale") == true)
        #expect(values?["theme"] as? String == "forest")
        #expect((values?["zoom"] as? NSNumber)?.doubleValue == 1.4)
        #expect(renderer.canExport)
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
private func waitForState(
    renderer: MermaidRenderer,
    timeout: Duration,
    matches: (MermaidRenderer) -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout

    while !matches(renderer) {
        if clock.now >= deadline {
            Issue.record("Renderer state timed out after \(timeout): \(renderer.state)")
            return
        }
        try await Task.sleep(for: .milliseconds(50))
    }
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
