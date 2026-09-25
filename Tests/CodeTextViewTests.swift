import AppKit
import Testing

@testable import MacUML

@Suite("Code Text View Tests")
@MainActor
struct CodeTextViewTests {
    @Test("Replacing text preserves a caret after an emoji")
    func replacementPreservesCaretAfterEmoji() {
        let textView = CodeTextView()
        textView.string = "Troy 🍕 Abed"
        textView.setSelectedRange(NSRange(location: 7, length: 0))

        textView.setStringPreservingSelection("Troy 🍕 and Abed")

        #expect(textView.selectedRange() == NSRange(location: 7, length: 0))
    }

    @Test("Formatting keeps a caret at the document end")
    func formattingKeepsCaretAtEnd() {
        let textView = CodeTextView()
        textView.string = "flowchart TD   "
        textView.setSelectedRange(NSRange(location: 15, length: 0))

        textView.setStringPreservingSelection(MermaidFormatter.format(textView.string))

        #expect(textView.string == "flowchart TD\n")
        #expect(textView.selectedRange() == NSRange(location: 13, length: 0))
    }

    @Test("Replacing with empty text preserves a valid caret")
    func emptyReplacementPreservesValidCaret() {
        let textView = CodeTextView()
        textView.string = "Greendale"
        textView.setSelectedRange(NSRange(location: 5, length: 0))

        textView.setStringPreservingSelection("")

        #expect(textView.selectedRange() == NSRange(location: 0, length: 0))
    }

    @Test("Editing text rebuilds line offsets")
    func editingTextRebuildsLineOffsets() {
        let textView = CodeTextView()
        textView.string = "Troy\nAbed"
        textView.applyInitialHighlighting()
        textView.setSelectedRange(NSRange(location: 4, length: 0))

        textView.insertText("\nShirley", replacementRange: textView.selectedRange())

        #expect(textView.string == "Troy\nShirley\nAbed")
        #expect(textView.lineStartOffsets == [0, 5, 13])
    }

    @Test("Indenting a selected document preserves its final newline")
    func indentPreservesFinalNewline() {
        let textView = CodeTextView()
        textView.string = "Troy\nAbed\n"
        textView.setSelectedRange(NSRange(location: 0, length: textView.string.utf16.count))

        textView.indentSelection()

        #expect(textView.string == "    Troy\n    Abed\n")
    }

    @Test("Unindenting a selected document preserves its final newline")
    func unindentPreservesFinalNewline() {
        let textView = CodeTextView()
        textView.string = "    Troy\n    Abed\n"
        textView.setSelectedRange(NSRange(location: 0, length: textView.string.utf16.count))

        textView.unindentSelection()

        #expect(textView.string == "Troy\nAbed\n")
    }

    @Test("Revealing a line focuses it and moves the caret to its start")
    func revealLineFocusesLine() {
        let textView = CodeTextView()
        let scrollView = NSScrollView()
        scrollView.documentView = textView
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [], backing: .buffered,
            defer: false)
        window.contentView = scrollView
        textView.string = "Troy\nAbed\nAnnie"
        textView.applyInitialHighlighting()

        textView.revealLine(3)

        #expect(window.firstResponder === textView)
        #expect(textView.selectedRange() == NSRange(location: 10, length: 0))
    }
}
