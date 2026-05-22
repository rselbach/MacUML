import Testing
import AppKit
@testable import MacUML

@Suite("Line Number Ruler View Tests")
@MainActor
struct LineNumberRulerViewTests {
    // Note: LineNumberRulerView requires a CodeTextView in an NSScrollView,
    // so we test the line offset logic via CodeTextView's exposed lineStartOffsets

    @Test("Empty text has single line offset at 0")
    func emptyTextLineOffsets() {
        let textView = CodeTextView()
        textView.string = ""

        // Trigger rebuild via didChangeText simulation
        textView.applyInitialHighlighting()

        #expect(textView.lineStartOffsets == [0])
    }

    @Test("Single line text has one offset")
    func singleLineOffsets() {
        let textView = CodeTextView()
        textView.string = "Hello, World!"
        textView.applyInitialHighlighting()

        #expect(textView.lineStartOffsets == [0])
    }

    @Test("Two lines have two offsets")
    func twoLineOffsets() {
        let textView = CodeTextView()
        textView.string = "Line one\nLine two"
        textView.applyInitialHighlighting()

        #expect(textView.lineStartOffsets.count == 2)
        #expect(textView.lineStartOffsets[0] == 0)
        #expect(textView.lineStartOffsets[1] == 9) // "Line one\n" is 9 chars
    }

    @Test("Multiple lines tracked correctly")
    func multipleLineOffsets() {
        let textView = CodeTextView()
        textView.string = "A\nB\nC\nD"
        textView.applyInitialHighlighting()

        // 4 lines: A, B, C, D
        // Offsets: 0, 2, 4, 6
        #expect(textView.lineStartOffsets == [0, 2, 4, 6])
    }

    @Test("Line start offset lookup returns correct offset")
    func lineStartOffsetLookup() {
        let textView = CodeTextView()
        textView.string = "First\nSecond\nThird"
        textView.applyInitialHighlighting()

        #expect(textView.lineStartOffset(for: 1) == 0)   // "First" starts at 0
        #expect(textView.lineStartOffset(for: 2) == 6)   // "Second" starts at 6
        #expect(textView.lineStartOffset(for: 3) == 13)  // "Third" starts at 13
    }

    @Test("Line start offset returns nil for invalid line numbers")
    func invalidLineStartOffset() {
        let textView = CodeTextView()
        textView.string = "One\nTwo"
        textView.applyInitialHighlighting()

        #expect(textView.lineStartOffset(for: 0) == nil)  // Line numbers are 1-based
        #expect(textView.lineStartOffset(for: -1) == nil)
        #expect(textView.lineStartOffset(for: 100) == nil)
    }

    @Test("Trailing newline handled correctly")
    func trailingNewline() {
        let textView = CodeTextView()
        textView.string = "A\nB\n"
        textView.applyInitialHighlighting()

        // "A\n" (offset 0), "B\n" (offset 2)
        // Trailing newline doesn't create an empty line entry
        #expect(textView.lineStartOffsets == [0, 2])
    }

    @Test("Windows-style line endings")
    func windowsLineEndings() {
        let textView = CodeTextView()
        textView.string = "A\r\nB\r\nC"
        textView.applyInitialHighlighting()

        // \r\n is treated as single line ending by NSString
        // "A\r\n" (0), "B\r\n" (3), "C" (6)
        #expect(textView.lineStartOffsets.count == 3)
    }

    @Test("Formatting refreshes line offsets")
    func formattingRefreshesLineOffsets() {
        let textView = CodeTextView()
        textView.string = "A\n\n\nB   "
        textView.applyInitialHighlighting()

        textView.performFormat()

        #expect(textView.string == "A\n\nB\n")
        #expect(textView.lineStartOffsets == [0, 2, 3])
    }
}
