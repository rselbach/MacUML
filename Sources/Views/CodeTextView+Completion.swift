import AppKit

extension CodeTextView {
    /// Characters a word needs before typing opens the completion list.
    private static let typedCompletionLength = 2

    /// Shows suggestions for the word before the caret, or hides the list when there are none.
    func showCompletions(minimumLength: Int = 0) {
        let selection = selectedRange()
        guard selection.length == 0, !hasMarkedText(),
            let completions = MermaidCompletion.completions(
                in: string as NSString, at: selection.location, minimumLength: minimumLength)
        else {
            dismissCompletions()
            return
        }
        present(completions)
    }

    /// Opens the completion list once typing makes a word long enough. Accepted suggestions and pasted text,
    /// which arrive as more than one character, leave it closed.
    func showCompletions(afterTyping typed: String) {
        guard activeCompletions == nil, typed.count == 1 else { return }
        showCompletions(minimumLength: Self.typedCompletionLength)
    }

    /// Replaces the partial word with `suggestion`, or with the selected suggestion, as its own undo step.
    func acceptCompletion(_ suggestion: String? = nil) {
        guard let activeCompletions, let suggestion = suggestion ?? completionPanel.selectedSuggestion else { return }
        dismissCompletions()
        breakUndoCoalescing()
        insertText(suggestion, replacementRange: activeCompletions.range)
        breakUndoCoalescing()
    }

    @objc func dismissCompletions() {
        guard activeCompletions != nil else { return }
        activeCompletions = nil
        completionPanel.dismiss()
        NotificationCenter.default.removeObserver(self, name: NSView.boundsDidChangeNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: nil)
    }

    private func present(_ completions: MermaidCompletion.Completions) {
        if activeCompletions == nil, let window, let clipView = enclosingScrollView?.contentView {
            NotificationCenter.default.addObserver(
                self, selector: #selector(repositionCompletions), name: NSView.boundsDidChangeNotification,
                object: clipView)
            // a child window stays on screen when its app deactivates
            NotificationCenter.default.addObserver(
                self, selector: #selector(dismissCompletions), name: NSWindow.didResignKeyNotification,
                object: window)
        }
        activeCompletions = completions
        completionPanel.show(
            completions.suggestions,
            font: font ?? .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular))
        repositionCompletions()
    }

    /// Keeps the list under its word as the editor scrolls, and hides it once the word scrolls out of view.
    @objc private func repositionCompletions() {
        guard let activeCompletions, let window else { return }
        let wordRect = firstRect(forCharacterRange: activeCompletions.range, actualRange: nil)
        let visibleWord = convert(window.convertFromScreen(wordRect), from: nil)
        guard visibleRect.contains(NSPoint(x: visibleWord.minX, y: visibleWord.midY)) else {
            dismissCompletions()
            return
        }
        completionPanel.present(below: wordRect, in: window)
    }

    // typing and deleting within the word refine the list; any other change of selection hides it
    override func setSelectedRanges(
        _ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting stillSelectingFlag: Bool
    ) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelectingFlag)
        guard let activeCompletions else { return }
        let selection = selectedRange()
        guard selection.length == 0, !hasMarkedText(),
            let refined = MermaidCompletion.completions(
                in: string as NSString, at: selection.location, minimumLength: 1),
            refined.range.location == activeCompletions.range.location
        else {
            dismissCompletions()
            return
        }
        present(refined)
    }

    // Option-Escape and F5 arrive here
    override func complete(_ sender: Any?) {
        guard activeCompletions == nil else {
            dismissCompletions()
            return
        }
        showCompletions()
    }

    // Escape closes the list; without one, NSTextView passes it on to the window
    override func doCommand(by selector: Selector) {
        guard selector == #selector(cancelOperation(_:)), activeCompletions != nil else {
            super.doCommand(by: selector)
            return
        }
        dismissCompletions()
    }

    override func moveUp(_ sender: Any?) {
        guard activeCompletions == nil else {
            completionPanel.moveSelection(by: -1)
            return
        }
        super.moveUp(sender)
    }

    override func moveDown(_ sender: Any?) {
        guard activeCompletions == nil else {
            completionPanel.moveSelection(by: 1)
            return
        }
        super.moveDown(sender)
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            dismissCompletions()
        }
        return resigned
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        dismissCompletions()
        super.viewWillMove(toWindow: newWindow)
    }
}
