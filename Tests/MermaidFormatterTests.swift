import Testing
@testable import MacUML

@Suite("Mermaid Formatter Tests")
struct MermaidFormatterTests {
    @Test("Empty input remains empty")
    func emptyInput() {
        #expect(MermaidFormatter.format("") == "")
    }

    @Test("Adds one trailing newline for non-empty input")
    func addsTrailingNewline() {
        #expect(MermaidFormatter.format("flowchart TD") == "flowchart TD\n")
        #expect(MermaidFormatter.format("flowchart TD\n\n") == "flowchart TD\n")
    }

    @Test("Trims trailing whitespace without changing indentation")
    func trimsTrailingWhitespace() {
        let source = "flowchart TD   \n    A-->B\t"

        let formatted = MermaidFormatter.format(source)

        #expect(formatted == "flowchart TD\n    A-->B\n")
    }

    @Test("Collapses consecutive blank lines")
    func collapsesConsecutiveBlankLines() {
        let source = "flowchart TD\n\n\nA-->B\n\n\nB-->C"

        let formatted = MermaidFormatter.format(source)

        #expect(formatted == "flowchart TD\n\nA-->B\n\nB-->C\n")
    }

    @Test("Normalizes line endings")
    func normalizesLineEndings() {
        let source = "flowchart TD\r\nA-->B\rB-->C"

        let formatted = MermaidFormatter.format(source)

        #expect(formatted == "flowchart TD\nA-->B\nB-->C\n")
    }

    @Test("Preserves arrows, comments, labels, and quoted strings")
    func preservesMermaidSyntax() {
        let source = """
        flowchart TD
        %% comment keeps A-->B and --o
        A--oB
        A["label with A-->B"]
        B-->|"quoted A-->B"|C
        """

        let formatted = MermaidFormatter.format(source)

        #expect(formatted == source + "\n")
    }
}
