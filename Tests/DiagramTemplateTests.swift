import Testing

@testable import MacUML

@Suite("Diagram Template Tests", .serialized)
struct DiagramTemplateTests {
    @Test("Templates have distinct titles")
    func templatesHaveDistinctTitles() {
        let titles = DiagramTemplate.allCases.map(\.title)
        #expect(Set(titles).count == DiagramTemplate.allCases.count)
    }

    @Test("Diagram templates start with valid Mermaid declarations")
    func diagramTemplatesStartWithMermaidDeclarations() {
        #expect(DiagramTemplate.blank.source.isEmpty)
        #expect(DiagramTemplate.flowchart.source.hasPrefix("flowchart"))
        #expect(DiagramTemplate.sequence.source.hasPrefix("sequenceDiagram"))
        #expect(DiagramTemplate.classDiagram.source.hasPrefix("classDiagram"))
        #expect(DiagramTemplate.state.source.hasPrefix("stateDiagram-v2"))
        #expect(DiagramTemplate.entityRelationship.source.hasPrefix("erDiagram"))
        #expect(DiagramTemplate.gantt.source.hasPrefix("gantt"))
        #expect(DiagramTemplate.pie.source.hasPrefix("pie"))
        #expect(DiagramTemplate.mindmap.source.hasPrefix("mindmap"))
        #expect(DiagramTemplate.timeline.source.hasPrefix("timeline"))
        #expect(DiagramTemplate.gitGraph.source.hasPrefix("gitGraph"))
    }

    @Test("Diagram templates render", arguments: DiagramTemplate.allCases.filter { $0 != .blank })
    @MainActor
    func diagramTemplatesRender(template: DiagramTemplate) async throws {
        let renderer = MermaidRenderer()
        renderer.render(source: template.source)

        let deadline = ContinuousClock.now + .seconds(5)
        while renderer.state != .ready, renderer.state.error == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }

        #expect(renderer.state == .ready, "\(template.title): \(renderer.state.error?.message ?? "timed out")")
    }

    @Test("Diagram templates use Community example data")
    func diagramTemplatesUseCommunityExamples() {
        for template in DiagramTemplate.allCases where template != .blank {
            #expect(template.source.contains("Troy") || template.source.contains("Abed"))
        }
    }
}
