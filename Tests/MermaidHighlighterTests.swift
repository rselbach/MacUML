import AppKit
import Testing
@testable import MacUML

@Suite("Mermaid Highlighter Tests")
@MainActor
struct MermaidHighlighterTests {

    // MARK: - Helpers

    private func foregroundColor(in storage: NSTextStorage, at index: Int) -> NSColor? {
        guard index < storage.length else { return nil }
        return storage.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor
    }

    private func makeStorage(_ text: String) async -> NSTextStorage {
        let storage = NSTextStorage(string: text)
        await MermaidHighlighter.shared.highlight(storage)
        return storage
    }

    // MARK: - Keywords

    @Test("Keywords are highlighted purple", arguments: [
        ("sequenceDiagram", 0, 14, "sequenceDiagram standalone"),
        ("participant Alice", 0, 10, "participant keyword"),
        ("subgraph cluster_A", 0, 7, "subgraph keyword"),
        ("end", 0, 2, "end keyword"),
    ])
    func keywordHighlighting(text: String, start: Int, end: Int, label: String) async {
        let storage = await makeStorage(text)
        for i in start...end {
            let color = foregroundColor(in: storage, at: i)
            #expect(
                color == .systemPurple,
                "'\(label)' char \(i) ('\(text[text.index(text.startIndex, offsetBy: i)])') want purple, got \(String(describing: color))"
            )
        }
    }

    @Test("flowchart TD highlights both keywords purple")
    func flowchartDirectionKeywords() async {
        let storage = await makeStorage("flowchart TD")
        // "flowchart" at 0..8
        for i in 0...8 {
            #expect(foregroundColor(in: storage, at: i) == .systemPurple, "flowchart char \(i)")
        }
        // "TD" at 10..11
        for i in 10...11 {
            #expect(foregroundColor(in: storage, at: i) == .systemPurple, "TD char \(i)")
        }
        // space at 9 should NOT be purple
        #expect(foregroundColor(in: storage, at: 9) != .systemPurple, "space between keywords should not be purple")
    }

    // MARK: - Comments

    @Test("Line comments are highlighted green")
    func commentHighlighting() async {
        let text = "%% this is a comment"
        let storage = await makeStorage(text)
        for i in 0..<text.count {
            #expect(
                foregroundColor(in: storage, at: i) == .systemGreen,
                "comment char \(i) want green"
            )
        }
    }

    @Test("Comments keep precedence over keywords, arrows, and nodes")
    func commentPrecedence() async {
        let text = "%% flowchart A-->B [Node]"
        let storage = await makeStorage(text)
        for i in 0..<text.count {
            #expect(
                foregroundColor(in: storage, at: i) == .systemGreen,
                "comment char \(i) should stay green"
            )
        }
    }

    // MARK: - Strings

    struct StringTestCase {
        let text: String
        let start: Int
        let end: Int
        let label: String
    }

    nonisolated static let stringCases: [StringTestCase] = [
        StringTestCase(text: "\"hello world\"", start: 0, end: 12, label: "double-quoted string"),
        StringTestCase(text: "'hello'", start: 0, end: 6, label: "single-quoted string"),
        StringTestCase(text: "|label text|", start: 0, end: 11, label: "pipe-delimited string"),
    ]

    @Test("Strings are highlighted red", arguments: stringCases)
    func stringHighlighting(tc: StringTestCase) async {
        let storage = await makeStorage(tc.text)
        for i in tc.start...tc.end {
            #expect(
                foregroundColor(in: storage, at: i) == .systemRed,
                "'\(tc.label)' char \(i) want red"
            )
        }
    }

    @Test("Strings keep precedence over keywords and arrows")
    func stringPrecedence() async {
        let text = "\"flowchart A-->B\""
        let storage = await makeStorage(text)
        for i in 0..<text.count {
            #expect(
                foregroundColor(in: storage, at: i) == .systemRed,
                "string char \(i) should stay red"
            )
        }
    }

    // MARK: - Arrows

    struct ArrowTestCase {
        let text: String
        let arrowStart: Int
        let arrowEnd: Int
        let label: String
    }

    nonisolated static let arrowCases: [ArrowTestCase] = [
        ArrowTestCase(text: "A-->>B", arrowStart: 1, arrowEnd: 4, label: "-->>"),
        ArrowTestCase(text: "A-->B", arrowStart: 1, arrowEnd: 3, label: "-->"),
        ArrowTestCase(text: "A==>B", arrowStart: 1, arrowEnd: 3, label: "==>"),
        ArrowTestCase(text: "A-.->B", arrowStart: 1, arrowEnd: 4, label: "-.->"),
    ]

    @Test("Arrows are highlighted blue", arguments: arrowCases)
    func arrowHighlighting(tc: ArrowTestCase) async {
        let storage = await makeStorage(tc.text)
        for i in tc.arrowStart...tc.arrowEnd {
            #expect(
                foregroundColor(in: storage, at: i) == .systemBlue,
                "'\(tc.label)' char \(i) want blue"
            )
        }
    }

    // MARK: - Nodes

    struct NodeTestCase {
        let text: String
        let nodeStart: Int
        let nodeEnd: Int
        let label: String
    }

    nonisolated static let nodeCases: [NodeTestCase] = [
        NodeTestCase(text: "A[Box Label]", nodeStart: 1, nodeEnd: 11, label: "square brackets"),
        NodeTestCase(text: "A(Round Label)", nodeStart: 1, nodeEnd: 13, label: "parentheses"),
        NodeTestCase(text: "A{Diamond}", nodeStart: 1, nodeEnd: 9, label: "curly braces"),
    ]

    @Test("Nodes are highlighted orange", arguments: nodeCases)
    func nodeHighlighting(tc: NodeTestCase) async {
        let storage = await makeStorage(tc.text)
        for i in tc.nodeStart...tc.nodeEnd {
            #expect(
                foregroundColor(in: storage, at: i) == .systemOrange,
                "'\(tc.label)' char \(i) want orange"
            )
        }
    }

    // MARK: - Directives

    @Test("Directives are highlighted teal")
    func directiveHighlighting() async {
        let text = "%%{init: {'theme':'forest'}}%%"
        let storage = await makeStorage(text)
        for i in 0..<text.count {
            #expect(
                foregroundColor(in: storage, at: i) == .systemTeal,
                "directive char \(i) want teal"
            )
        }
    }

    // MARK: - Incremental highlighting

    @Test("Incremental highlight only affects edited range lines")
    func incrementalHighlight() async {
        let text = "sequenceDiagram\nparticipant Alice\nparticipant Bob"
        let storage = NSTextStorage(string: text)

        // Full highlight first
        await MermaidHighlighter.shared.highlight(storage)

        // Verify line 1 "participant" is purple
        let line2Start = 16 // "participant" on second line
        #expect(foregroundColor(in: storage, at: line2Start) == .systemPurple, "line 2 keyword before incremental")

        // Now do incremental highlight on line 3 only (range covering "participant Bob")
        let line3Start = 35 // "participant Bob" starts here
        let editRange = NSRange(location: line3Start, length: 15)
        await MermaidHighlighter.shared.highlight(storage, in: editRange)

        // Line 2 should still be purple (untouched by incremental)
        #expect(foregroundColor(in: storage, at: line2Start) == .systemPurple, "line 2 keyword after incremental")

        // Line 3 keyword should also be purple
        #expect(foregroundColor(in: storage, at: line3Start) == .systemPurple, "line 3 keyword after incremental")
    }

    // MARK: - Edge cases

    @Test("Empty string does not crash")
    func emptyString() async {
        let storage = await makeStorage("")
        #expect(storage.length == 0)
    }

    @Test("Plain text gets default text color")
    func plainText() async {
        let text = "just some plain text"
        let storage = await makeStorage(text)
        for i in 0..<text.count {
            #expect(
                foregroundColor(in: storage, at: i) == .textColor,
                "plain text char \(i) want default textColor"
            )
        }
    }
}

// MARK: - Conformances for parameterized tests

extension MermaidHighlighterTests.StringTestCase: CustomTestStringConvertible, Sendable {
    var testDescription: String { label }
}

extension MermaidHighlighterTests.ArrowTestCase: CustomTestStringConvertible, Sendable {
    var testDescription: String { label }
}

extension MermaidHighlighterTests.NodeTestCase: CustomTestStringConvertible, Sendable {
    var testDescription: String { label }
}
