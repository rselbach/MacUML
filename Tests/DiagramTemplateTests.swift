import Testing

@testable import MacUML

@Suite("Diagram Template Tests")
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
    }

    @Test("Diagram templates use Community example data")
    func diagramTemplatesUseCommunityExamples() {
        for template in DiagramTemplate.allCases where template != .blank {
            #expect(template.source.contains("Troy") || template.source.contains("Abed"))
        }
    }
}
