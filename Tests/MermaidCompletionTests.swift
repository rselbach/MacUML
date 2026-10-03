import Foundation
import Testing

@testable import MacUML

@Suite("Mermaid Completion Tests")
struct MermaidCompletionTests {
    @Test(
        "Suggestions fit where the caret is",
        arguments: [
            ("seq‸", ["sequenceDiagram"]),
            ("---\nconfig:\n  theme: dark\n---\n%% Greendale\nfl‸", ["flowchart"]),
            ("---\ncon‸", nil),
            ("stateDiagram-‸", ["stateDiagram-v2"]),
            ("sequenceDiagram\n    pa‸", ["participant", "par"]),
            ("sequenceDiagram\n    loop Every minute\n        no‸", ["Note"]),
            ("sequenceDiagram\n    Troy pa‸", nil),
            ("gitGraph\n    cherry-p‸", ["cherry-pick"]),
            ("mindmap\n    Greendale\n        Gr‸", ["Greendale"]),
            ("flowchart LR\n    Troy --> Abed\n    Troy --> ab‸", ["Abed"]),
            ("flowchart LR\n    Troy-->Abed\n    Troy---Annie\n    Tr‸", ["Troy"]),
            ("flowchart LR\n    Shirley --> Study\n    st‸", ["style", "Study"]),
            ("flowchart LR\n    End --> Troy\n    end‸", nil),
            ("flowchart LR\n    Troy --> Abed\n    Ab‸ed", nil),
            ("gantt\n    Troy scouts :scout, 2026-03-02, 3d\n    Abed :20‸", nil),
            ("pie title Snacks\n    \"Troy's popcorn\" : 45\n    \"po‸", ["popcorn"]),
        ])
    func suggestions(source: String, want: [String]?) {
        let caret = (source as NSString).range(of: "‸").location
        let text = source.replacingOccurrences(of: "‸", with: "") as NSString

        let completions = MermaidCompletion.completions(in: text, at: caret)

        #expect(completions?.suggestions == want)
    }

    @Test("Completions replace the whole partial word, hyphens included")
    func completionRangeCoversPartialWord() throws {
        let text = "gitGraph\n    cherry-p" as NSString

        let completions = try #require(MermaidCompletion.completions(in: text, at: text.length))

        #expect(completions.range == NSRange(location: 13, length: 8))
    }

    @Test("An empty document offers every diagram type")
    func emptyDocumentOffersDiagramTypes() {
        let completions = MermaidCompletion.completions(in: "", at: 0)

        #expect(completions?.suggestions == MermaidCompletion.diagramTypes)
    }

    @Test("A word shorter than the minimum length gets no suggestions")
    func minimumLength() {
        let text = "flowchart LR\n    Troy --> Abed\n    T" as NSString

        #expect(MermaidCompletion.completions(in: text, at: text.length, minimumLength: 2) == nil)
        #expect(MermaidCompletion.completions(in: text, at: text.length)?.suggestions == ["Troy"])
    }
}
