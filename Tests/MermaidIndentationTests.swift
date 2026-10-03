import AppKit
import Testing

@testable import MacUML

@Suite("Mermaid Indentation Tests")
@MainActor
struct MermaidIndentationTests {
    @Test(
        "Return indents blocks and realigns the lines that close them",
        arguments: [
            ("flowchart LR‸", "flowchart LR\n    ‸"),
            (
                "---\nconfig:\n  theme: dark\n---\n%% Study Room F\nsequenceDiagram‸",
                "---\nconfig:\n  theme: dark\n---\n%% Study Room F\nsequenceDiagram\n    ‸"
            ),
            ("---\nconfig:‸", "---\nconfig:\n‸"),
            ("flowchart LR\n    subgraph Greendale‸", "flowchart LR\n    subgraph Greendale\n        ‸"),
            ("sequenceDiagram\n    loop Every minute‸", "sequenceDiagram\n    loop Every minute\n        ‸"),
            ("classDiagram\n    class Troy {‸", "classDiagram\n    class Troy {\n        ‸"),
            (
                "sequenceDiagram\n    loop Every minute\n        Troy->>Abed: Ping\n        end‸",
                "sequenceDiagram\n    loop Every minute\n        Troy->>Abed: Ping\n    end\n    ‸"
            ),
            (
                "flowchart LR\n    subgraph Greendale\n        subgraph Study Room F\n            Troy --> Abed\n        end\n        end‸",
                "flowchart LR\n    subgraph Greendale\n        subgraph Study Room F\n            Troy --> Abed\n        end\n    end\n    ‸"
            ),
            (
                "sequenceDiagram\n    alt Paintball\n        Troy->>Abed: Hide\n        else Truce‸",
                "sequenceDiagram\n    alt Paintball\n        Troy->>Abed: Hide\n    else Truce\n        ‸"
            ),
            (
                "classDiagram\n    class Troy {\n        +present()\n        }‸",
                "classDiagram\n    class Troy {\n        +present()\n    }\n    ‸"
            ),
            (
                "gantt\n    section Planning\n        Troy scouts the campus :2026-03-02, 3d\n        section Game‸",
                "gantt\n    section Planning\n        Troy scouts the campus :2026-03-02, 3d\n    section Game\n        ‸"
            ),
            ("flowchart LR\n    loop --> Abed‸", "flowchart LR\n    loop --> Abed\n    ‸"),
            ("flowchart LR\n    %% Greendale {‸", "flowchart LR\n    %% Greendale {\n    ‸"),
            ("flowchart LR\n        end‸", "flowchart LR\n        end\n        ‸"),
        ])
    func returnIndentsBlocks(source: String, want: String) {
        let textView = editor(source)

        textView.insertNewline(nil)

        #expect(rendered(textView) == want)
    }

    @Test(
        "Completing a closing keyword realigns its line",
        arguments: [
            (
                "sequenceDiagram\n    alt Paintball\n        Troy->>Abed: Hide\n        else‸", " ",
                "sequenceDiagram\n    alt Paintball\n        Troy->>Abed: Hide\n    else ‸"
            ),
            (
                "flowchart LR\n    subgraph Greendale\n        Troy --> Abed\n        end‸", " ",
                "flowchart LR\n    subgraph Greendale\n        Troy --> Abed\n    end ‸"
            ),
            (
                "classDiagram\n    class Troy {\n        +present()\n        ‸", "}",
                "classDiagram\n    class Troy {\n        +present()\n    }‸"
            ),
            (
                "sequenceDiagram\n    alt Paintball\n        elsewhere‸", " ",
                "sequenceDiagram\n    alt Paintball\n        elsewhere ‸"
            ),
            (
                "sequenceDiagram\n    alt Paintball\n        else Truce‸", " ",
                "sequenceDiagram\n    alt Paintball\n        else Truce ‸"
            ),
            (
                "flowchart LR\n    subgraph Greendale\n        option‸", " ",
                "flowchart LR\n    subgraph Greendale\n        option ‸"
            ),
        ])
    func typingRealignsClosers(source: String, typed: String, want: String) {
        let textView = editor(source)

        textView.insertText(typed, replacementRange: textView.selectedRange())

        #expect(rendered(textView) == want)
    }

    @Test(
        "Key presses realign closers",
        arguments: [
            (
                "sequenceDiagram\n    alt Paintball\n        Troy->>Abed: Hide\n        ‸", "else ",
                "sequenceDiagram\n    alt Paintball\n        Troy->>Abed: Hide\n    else ‸"
            ),
            (
                "flowchart LR\n    subgraph Greendale\n        Troy --> Abed\n        ‸", "end\r",
                "flowchart LR\n    subgraph Greendale\n        Troy --> Abed\n    end\n    ‸"
            ),
        ])
    func keyPressesRealignClosers(source: String, keys: String, want: String) throws {
        let (window, textView) = windowedEditor(source)

        try press(keys, in: textView)

        #expect(rendered(textView) == want)
        window.close()
    }

    @Test("One undo reverts Return and the realignment it made")
    func undoRevertsRealigningReturn() throws {
        let (window, textView) = windowedEditor("flowchart LR\n    subgraph Greendale\n        Troy --> Abed\n        ‸")
        let undoManager = try #require(textView.undoManager)
        undoManager.groupsByEvent = false
        defer { undoManager.groupsByEvent = true }
        try press("end", in: textView)
        let typed = rendered(textView)

        try press("\r", in: textView)
        undoManager.undo()

        #expect(rendered(textView) == typed)
        window.close()
    }

    private func editor(_ source: String) -> CodeTextView {
        let textView = CodeTextView()
        let caret = (source as NSString).range(of: "‸").location
        textView.string = source.replacingOccurrences(of: "‸", with: "")
        textView.setSelectedRange(NSRange(location: caret, length: 0))
        return textView
    }

    private func rendered(_ textView: CodeTextView) -> String {
        (textView.string as NSString).replacingCharacters(in: textView.selectedRange(), with: "‸")
    }

    private func windowedEditor(_ source: String) -> (NSWindow, CodeTextView) {
        let textView = editor(source)
        textView.allowsUndo = true
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [], backing: .buffered,
            defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = textView
        window.makeFirstResponder(textView)
        return (window, textView)
    }

    /// Sends each key as its own undo group, the way separate key events reach the app.
    private func press(_ keys: String, in textView: CodeTextView) throws {
        let keyCodes: [Character: UInt16] = ["e": 14, "n": 45, "d": 2, "l": 37, "s": 1, " ": 49, "\r": 36]
        for key in keys {
            let keyCode = try #require(keyCodes[key])
            let event = try #require(
                NSEvent.keyEvent(
                    with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                    windowNumber: textView.window?.windowNumber ?? 0, context: nil, characters: String(key),
                    charactersIgnoringModifiers: String(key), isARepeat: false, keyCode: keyCode))
            textView.undoManager?.beginUndoGrouping()
            textView.keyDown(with: event)
            textView.undoManager?.endUndoGrouping()
        }
    }
}
