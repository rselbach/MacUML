import AppKit
import Testing

@testable import MacUML

@Suite("Code Text View Completion Tests")
@MainActor
struct CodeTextViewCompletionTests {
    @Test("Typing two characters opens the list, and Tab accepts the first suggestion")
    func tabAcceptsFirstSuggestion() throws {
        let (window, textView) = windowedEditor("sequenceDiagram\n    ‸")
        let undoManager = try #require(textView.undoManager)
        undoManager.groupsByEvent = false
        defer { undoManager.groupsByEvent = true }

        try press("p", in: textView)
        #expect(textView.activeCompletions == nil)

        try press("a", in: textView)
        #expect(textView.activeCompletions?.suggestions == ["participant", "par"])
        #expect(textView.completionPanel.parent === window)

        try press("\t", in: textView)
        #expect(rendered(textView) == "sequenceDiagram\n    participant‸")
        #expect(textView.activeCompletions == nil)
        #expect(textView.completionPanel.parent == nil)

        undoManager.undo()
        #expect(rendered(textView) == "sequenceDiagram\n    pa‸")
        window.close()
    }

    @Test("Return accepts the suggestion chosen with the arrow keys")
    func returnAcceptsChosenSuggestion() throws {
        let (window, textView) = windowedEditor("sequenceDiagram\n    ‸")

        try press("pa", in: textView)
        try press(.downArrow, in: textView)
        try press(.downArrow, in: textView)
        try press(.upArrow, in: textView)
        try press(.downArrow, in: textView)
        try press("\r", in: textView)

        #expect(rendered(textView) == "sequenceDiagram\n    par‸")
        window.close()
    }

    @Test("Typing narrows the list and closes it once the word is complete")
    func typingNarrowsList() throws {
        let (window, textView) = windowedEditor("flowchart LR\n    Troy --> Abed\n    Abed --> Annie\n    ‸")

        try press("A", in: textView)
        #expect(textView.activeCompletions == nil)
        try press("n", in: textView)
        #expect(textView.activeCompletions?.suggestions == ["Annie"])
        try press("nie", in: textView)
        #expect(textView.activeCompletions == nil)

        try press("\r", in: textView)
        #expect(rendered(textView) == "flowchart LR\n    Troy --> Abed\n    Abed --> Annie\n    Annie\n    ‸")
        window.close()
    }

    @Test("Option-Escape opens and closes the list, and Escape closes it")
    func escapeKeysToggleList() throws {
        let (window, textView) = windowedEditor("sequenceDiagram\n    ‸")

        try press(.optionEscape, in: textView)
        #expect(textView.activeCompletions?.suggestions.first == "participant")
        try press(.optionEscape, in: textView)
        #expect(textView.activeCompletions == nil)

        try press(.optionEscape, in: textView)
        try press(.escape, in: textView)
        #expect(textView.activeCompletions == nil)
        #expect(rendered(textView) == "sequenceDiagram\n    ‸")
        window.close()
    }

    @Test("Typing a space or moving the caret closes the list")
    func leavingWordClosesList() throws {
        let (window, textView) = windowedEditor("sequenceDiagram\n    ‸")

        try press("pa", in: textView)
        try press(" ", in: textView)
        #expect(textView.activeCompletions == nil)
        #expect(rendered(textView) == "sequenceDiagram\n    pa ‸")

        for _ in 0..<3 {
            try press(.delete, in: textView)
        }
        try press("pa", in: textView)
        #expect(textView.activeCompletions != nil)
        try press(.leftArrow, in: textView)
        #expect(textView.activeCompletions == nil)
        #expect(rendered(textView) == "sequenceDiagram\n    p‸a")

        try press(.downArrow, in: textView)
        #expect(rendered(textView) == "sequenceDiagram\n    pa‸")
        window.close()
    }

    @Test("Deleting a character widens the list")
    func deletingWidensList() throws {
        let (window, textView) = windowedEditor("sequenceDiagram\n    ‸")

        try press("par", in: textView)
        #expect(textView.activeCompletions?.suggestions == ["participant"])

        try press(.delete, in: textView)
        #expect(textView.activeCompletions?.suggestions == ["participant", "par"])
        window.close()
    }

    private enum Key {
        case delete
        case escape
        case optionEscape
        case leftArrow
        case upArrow
        case downArrow

        var keyCode: UInt16 {
            switch self {
            case .delete: 51
            case .escape, .optionEscape: 53
            case .leftArrow: 123
            case .downArrow: 125
            case .upArrow: 126
            }
        }

        var characters: String {
            switch self {
            case .delete: "\u{7F}"
            case .escape, .optionEscape: "\u{1B}"
            case .leftArrow: "\u{F702}"
            case .downArrow: "\u{F701}"
            case .upArrow: "\u{F700}"
            }
        }

        var modifierFlags: NSEvent.ModifierFlags {
            self == .optionEscape ? .option : []
        }
    }

    private func rendered(_ textView: CodeTextView) -> String {
        (textView.string as NSString).replacingCharacters(in: textView.selectedRange(), with: "‸")
    }

    private func windowedEditor(_ source: String) -> (NSWindow, CodeTextView) {
        let textView = CodeTextView()
        textView.allowsUndo = true
        let caret = (source as NSString).range(of: "‸").location
        textView.string = source.replacingOccurrences(of: "‸", with: "")
        textView.setSelectedRange(NSRange(location: caret, length: 0))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [], backing: .buffered,
            defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = textView
        window.makeFirstResponder(textView)
        return (window, textView)
    }

    /// Sends each character as its own key event and undo group, the way typing reaches the app.
    private func press(_ keys: String, in textView: CodeTextView) throws {
        let keyCodes: [Character: UInt16] = ["\t": 48, "\r": 36, " ": 49]
        for key in keys {
            try send(keyCode: keyCodes[key] ?? 0, characters: String(key), modifierFlags: [], to: textView)
        }
    }

    private func press(_ key: Key, in textView: CodeTextView) throws {
        try send(keyCode: key.keyCode, characters: key.characters, modifierFlags: key.modifierFlags, to: textView)
    }

    private func send(
        keyCode: UInt16, characters: String, modifierFlags: NSEvent.ModifierFlags, to textView: CodeTextView
    ) throws {
        let event = try #require(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: modifierFlags, timestamp: 0,
                windowNumber: textView.window?.windowNumber ?? 0, context: nil, characters: characters,
                charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode))
        textView.undoManager?.beginUndoGrouping()
        textView.keyDown(with: event)
        textView.undoManager?.endUndoGrouping()
    }
}
