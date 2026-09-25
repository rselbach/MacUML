import AppKit
import Foundation
import Testing

@testable import MacUML

@Suite("DiagramExporter Tests")
struct DiagramExporterTests {
    @Test("PNG export succeeds with complete labeled content")
    @MainActor
    func pngExportSucceeds() async throws {
        let renderer = MermaidRenderer()
        renderer.render(source: "flowchart LR\nA[\"Troy Barnes\"] --> B[\"Greendale Community College\"]")
        try await waitForRenderCompletion(renderer: renderer, timeout: .seconds(5))

        let data = try requireSuccess(await DiagramExporter(webView: renderer.webView).copyAsPNG())
        let bitmap = try #require(NSBitmapImageRep(data: data))

        #expect(bitmap.pixelsWide > 100)
        #expect(bitmap.pixelsHigh > 20)
        #expect(nonTransparentPixelCount(in: bitmap) > 100)

        renderer.render(source: "flowchart LR\nA[\"Shirley Bennett\"] --> B[\"Study Room F\"]")
        try await waitForRenderCompletion(renderer: renderer, timeout: .seconds(5))
        let changedLabelsData = try requireSuccess(await DiagramExporter(webView: renderer.webView).copyAsPNG())
        #expect(changedLabelsData != data)
    }

    @Test("PNG padding changes intrinsic dimensions")
    @MainActor
    func pngPaddingChangesDimensions() async throws {
        let renderer = MermaidRenderer()
        renderer.render(source: "flowchart TD\nA[\"Troy\"] --> B[\"Abed\"]")
        try await waitForRenderCompletion(renderer: renderer, timeout: .seconds(5))

        let exporter = DiagramExporter(webView: renderer.webView)
        let unpadded = try #require(NSBitmapImageRep(data: requireSuccess(await exporter.copyAsPNG(padding: 0))))
        let padded = try #require(NSBitmapImageRep(data: requireSuccess(await exporter.copyAsPNG(padding: 32))))

        #expect(padded.pixelsWide == unpadded.pixelsWide + 64)
        #expect(padded.pixelsHigh == unpadded.pixelsHigh + 64)
    }

    @Test("Exports are independent of preview zoom and pan")
    @MainActor
    func exportsIgnoreViewportTransform() async throws {
        let renderer = MermaidRenderer()
        renderer.render(source: "flowchart TD\nA[\"Troy\"] --> B[\"Abed\"] --> C[\"Annie\"]")
        try await waitForRenderCompletion(renderer: renderer, timeout: .seconds(5))

        let exporter = DiagramExporter(webView: renderer.webView)
        renderer.setZoom(0.5)
        _ = try await renderer.webView.evaluateJavaScript("window.setPan(40, -25);")
        let smallZoomSVG = try requireSuccess(await exporter.copySVG())
        let smallZoomPNG = try requireSuccess(await exporter.copyAsPNG())

        renderer.setZoom(2.0)
        _ = try await renderer.webView.evaluateJavaScript("window.setPan(-75, 60);")
        let largeZoomSVG = try requireSuccess(await exporter.copySVG())
        let largeZoomPNG = try requireSuccess(await exporter.copyAsPNG())

        #expect(smallZoomSVG == largeZoomSVG)
        #expect(smallZoomPNG == largeZoomPNG)
    }

    @Test("SVG export preserves labels for representative Mermaid diagrams")
    @MainActor
    func svgExportPreservesLabels() async throws {
        let fixtures: [(source: String, labels: [String])] = [
            (
                "flowchart TD\nA[\"Syntax error\"] --> B[\"Parse error\"]",
                ["Syntax error", "Parse error"]
            ),
            (
                "classDiagram\nclass StudyGroup\nclass Troy\nStudyGroup --> Troy : includes",
                ["StudyGroup", "Troy", "includes"]
            ),
            (
                "sequenceDiagram\nparticipant T as Troy\nparticipant A as Abed\nT->>A: Cool cool cool",
                ["Troy", "Abed", "Cool cool cool"]
            ),
        ]
        let renderer = MermaidRenderer()
        let exporter = DiagramExporter(webView: renderer.webView)

        for fixture in fixtures {
            renderer.render(source: fixture.source)
            try await waitForRenderCompletion(renderer: renderer, timeout: .seconds(5))
            let svg = try requireSuccess(await exporter.copySVG())
            for label in fixture.labels {
                #expect(svg.contains(label), "SVG should preserve label: \(label)")
            }
            #expect(svg.contains("viewBox="))
            #expect(svg.contains("width="))
            #expect(svg.contains("height="))

            let svgDocument = try XMLDocument(data: Data(svg.utf8))
            #expect(svgDocument.rootElement()?.name?.lowercased() == "svg")

            let png = try requireSuccess(await exporter.copyAsPNG())
            let bitmap = try #require(NSBitmapImageRep(data: png))
            #expect(bitmap.pixelsWide > 20)
            #expect(bitmap.pixelsHigh > 20)
            #expect(nonTransparentPixelCount(in: bitmap) > 100)
        }
    }

    @Test("Exports fail when no current diagram exists")
    @MainActor
    func exportsFailWithoutDiagram() async {
        let renderer = MermaidRenderer()
        let exporter = DiagramExporter(webView: renderer.webView)
        await waitForRuntimeReady(renderer: renderer, timeout: .seconds(5))

        #expect(await exporter.copyAsPNG() == .failure(.noDiagram))
        #expect(await exporter.copySVG() == .failure(.svgNotFound))
    }

    @Test("Context export reports disabled-action errors")
    @MainActor
    func contextExportReportsError() async {
        let renderer = MermaidRenderer()
        var receivedError: ExportError?
        renderer.exportErrorHandler = { receivedError = $0 }

        renderer.webView.copyPNGHandler?()
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(2)
        while receivedError == nil && clock.now < deadline {
            await Task.yield()
        }

        #expect(receivedError == .noDiagram)
        #expect(renderer.webView.canCopyHandler?() == false)
    }

}

@MainActor
private func waitForRuntimeReady(renderer: MermaidRenderer, timeout: Duration) async {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while !renderer.mermaidReady && clock.now < deadline {
        do {
            try await Task.sleep(for: .milliseconds(50))
        } catch {
            return
        }
    }
    #expect(renderer.mermaidReady)
}

private func requireSuccess<T>(_ result: Result<T, ExportError>) throws -> T {
    switch result {
    case .success(let value):
        return value
    case .failure(let error):
        Issue.record("Export failed: \(error.localizedDescription)")
        throw error
    }
}

private func nonTransparentPixelCount(in bitmap: NSBitmapImageRep) -> Int {
    var count = 0
    let step = max(1, min(bitmap.pixelsWide, bitmap.pixelsHigh) / 50)
    for y in stride(from: 0, to: bitmap.pixelsHigh, by: step) {
        for x in stride(from: 0, to: bitmap.pixelsWide, by: step) {
            if let color = bitmap.colorAt(x: x, y: y), color.alphaComponent > 0.01 {
                count += 1
            }
        }
    }
    return count
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
            throw error
        default:
            if clock.now >= deadline {
                Issue.record("Render timed out after \(timeout): \(renderer.state)")
                return
            }
            try await Task.sleep(for: .milliseconds(50))
        }
    } while true
}
