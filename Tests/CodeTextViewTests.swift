import AppKit
import SwiftUI
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

    @Test("Editor lifetime preserves undo and focus across layout changes")
    func editorLifetimePreservesUndoAndFocus() async throws {
        let model = EditorLifecycleModel()
        let hostingView = NSHostingView(rootView: EditorLifecycleHost(model: model))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [], backing: .buffered,
            defer: false)
        window.contentView = hostingView
        await refresh(hostingView)

        let textView = try #require(model.actions.textView)
        window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
        textView.insertText(" and Abed", replacementRange: textView.selectedRange())
        let undoManager = try #require(textView.undoManager)
        #expect(model.text == "Troy and Abed")
        #expect(window.firstResponder === textView)

        model.actions.rememberFocus()
        model.showsEditor = false
        await refresh(hostingView)
        #expect(textView.window == nil)

        undoManager.undo()
        #expect(model.text == "Troy")

        model.showsEditor = true
        await refresh(hostingView)
        #expect(model.actions.textView === textView)
        #expect(textView.window === window)
        #expect(textView.string == "Troy")
        #expect(window.firstResponder === textView)
    }

    @Test("Formatting from the document can be undone without disturbing earlier edits")
    func externalFormattingIsUndoable() async throws {
        let model = EditorLifecycleModel(text: "flowchart TD")
        let hostingView = NSHostingView(rootView: EditorLifecycleHost(model: model))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [], backing: .buffered,
            defer: false)
        window.contentView = hostingView
        await refresh(hostingView)

        let textView = try #require(model.actions.textView)
        window.makeFirstResponder(textView)
        let undoManager = try #require(textView.undoManager)
        // separate undo steps the way distinct key events would in the app
        undoManager.groupsByEvent = false
        defer { undoManager.groupsByEvent = true }
        func step(_ edit: () -> Void) {
            undoManager.beginUndoGrouping()
            edit()
            undoManager.endUndoGrouping()
        }

        textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
        step { textView.insertText("   \n\n\n", replacementRange: textView.selectedRange()) }
        step { textView.insertText("    Troy --> Abed", replacementRange: textView.selectedRange()) }
        let unformatted = model.text

        undoManager.beginUndoGrouping()
        model.text = MermaidFormatter.format(model.text)
        await refresh(hostingView)
        undoManager.endUndoGrouping()
        #expect(textView.string == "flowchart TD\n\n    Troy --> Abed\n")

        undoManager.undo()
        #expect(model.text == unformatted)
        undoManager.undo()
        #expect(model.text == "flowchart TD   \n\n\n")
        undoManager.redo()
        undoManager.redo()
        #expect(model.text == "flowchart TD\n\n    Troy --> Abed\n")
    }

    @Test("Changed ranges trim common text without splitting surrogate pairs")
    func changedRangesTrimCommonText() {
        let ranges = CodeTextView.changedRanges(from: "Troy 🍕 Abed", to: "Troy 🍔 Abed")
        #expect(ranges.old == NSRange(location: 5, length: 2))
        #expect(ranges.new == NSRange(location: 5, length: 2))

        let insertion = CodeTextView.changedRanges(from: "Troy", to: "Troy and Abed")
        #expect(insertion.old == NSRange(location: 4, length: 0))
        #expect(insertion.new == NSRange(location: 4, length: 9))
    }

    @Test("A queued line reveal runs after the editor attaches")
    func queuedLineRevealRunsAfterAttachment() async throws {
        let model = EditorLifecycleModel(text: "Troy\nAbed\nAnnie", showsEditor: false)
        let hostingView = NSHostingView(rootView: EditorLifecycleHost(model: model))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [], backing: .buffered,
            defer: false)
        window.contentView = hostingView
        await refresh(hostingView)

        model.actions.revealLine(3)
        model.showsEditor = true
        await refresh(hostingView)

        let textView = try #require(model.actions.textView)
        #expect(textView.selectedRange() == NSRange(location: 10, length: 0))
        #expect(window.firstResponder === textView)
    }

    private func refresh<Content: View>(_ hostingView: NSHostingView<Content>) async {
        hostingView.layoutSubtreeIfNeeded()
        await nextMainQueueTurn()
        hostingView.layoutSubtreeIfNeeded()
        await nextMainQueueTurn()
        await nextMainQueueTurn()
    }

    private func nextMainQueueTurn() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}

@MainActor
private final class EditorLifecycleModel: ObservableObject {
    @Published var text: String
    @Published var lineCount: Int
    @Published var showsEditor: Bool
    let actions = EditorActions()

    init(text: String = "Troy", showsEditor: Bool = true) {
        self.text = text
        lineCount = DocumentView.lineCount(in: text)
        self.showsEditor = showsEditor
    }
}

private struct EditorLifecycleHost: View {
    @ObservedObject var model: EditorLifecycleModel

    var body: some View {
        if model.showsEditor {
            EditorView(
                text: $model.text,
                lineCount: $model.lineCount,
                errorLine: nil,
                editorFont: .monospacedSystemFont(ofSize: 13, weight: .regular),
                showLineNumbers: true,
                actions: model.actions
            )
        } else {
            Color.clear
        }
    }
}
