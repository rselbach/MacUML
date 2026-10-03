import AppKit
import Carbon.HIToolbox.Events

extension CodeTextView {
    private enum KeyCode: UInt16 {
        case home
        case end
        case pageUp
        case pageDown
        case leftArrow
        case rightArrow
        case upArrow
        case downArrow

        init?(rawValue: UInt16) {
            switch Int(rawValue) {
            case kVK_Home: self = .home
            case kVK_End: self = .end
            case kVK_PageUp: self = .pageUp
            case kVK_PageDown: self = .pageDown
            case kVK_LeftArrow: self = .leftArrow
            case kVK_RightArrow: self = .rightArrow
            case kVK_UpArrow: self = .upArrow
            case kVK_DownArrow: self = .downArrow
            default: return nil
            }
        }
    }

    func handleKeyDown(_ event: NSEvent) -> Bool {
        // an input method composing text owns these keys
        guard !hasMarkedText() else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasShift = flags.contains(.shift)

        guard let keyCode = KeyCode(rawValue: event.keyCode) else {
            return false
        }

        switch keyCode {
        case .home:
            performMove(
                hasShift: hasShift, normal: #selector(moveToBeginningOfLine(_:)),
                modify: #selector(moveToBeginningOfLineAndModifySelection(_:)))
            return true
        case .end:
            performMove(
                hasShift: hasShift, normal: #selector(moveToEndOfLine(_:)),
                modify: #selector(moveToEndOfLineAndModifySelection(_:)))
            return true
        case .pageUp:
            performMove(
                hasShift: hasShift, normal: #selector(pageUp(_:)), modify: #selector(pageUpAndModifySelection(_:)))
            return true
        case .pageDown:
            performMove(
                hasShift: hasShift, normal: #selector(pageDown(_:)), modify: #selector(pageDownAndModifySelection(_:)))
            return true
        case .leftArrow:
            if flags.contains(.option) {
                performMove(
                    hasShift: hasShift, normal: #selector(moveWordBackward(_:)),
                    modify: #selector(moveWordBackwardAndModifySelection(_:)))
                return true
            }
        case .rightArrow:
            if flags.contains(.option) {
                performMove(
                    hasShift: hasShift, normal: #selector(moveWordForward(_:)),
                    modify: #selector(moveWordForwardAndModifySelection(_:)))
                return true
            }
        case .upArrow:
            if flags.contains(.option) {
                performMove(
                    hasShift: hasShift, normal: #selector(moveToBeginningOfParagraph(_:)),
                    modify: #selector(moveToBeginningOfParagraphAndModifySelection(_:)))
                return true
            }
        case .downArrow:
            if flags.contains(.command) {
                performMove(
                    hasShift: hasShift, normal: #selector(moveToEndOfDocument(_:)),
                    modify: #selector(moveToEndOfDocumentAndModifySelection(_:)))
                return true
            }
        }
        return false
    }

    private func performMove(hasShift: Bool, normal: Selector, modify: Selector) {
        if hasShift {
            perform(modify, with: nil)
        } else {
            perform(normal, with: nil)
        }
    }

    func indentSelection() {
        let range = selectedRange()
        let text = string as NSString

        if range.length == 0 {
            insertText(MermaidIndentation.unit, replacementRange: range)
            return
        }

        let lineRange = text.lineRange(for: range)
        let selectedText = text.substring(with: lineRange)
        var lines = selectedText.components(separatedBy: "\n")

        if lines.last == "" { lines.removeLast() }

        let indented = lines.map { MermaidIndentation.unit + $0 }.joined(separator: "\n")
        let finalText = selectedText.hasSuffix("\n") ? indented + "\n" : indented

        if shouldChangeText(in: lineRange, replacementString: finalText) {
            undoManager?.beginUndoGrouping()
            textStorage?.beginEditing()
            textStorage?.replaceCharacters(in: lineRange, with: finalText)
            textStorage?.endEditing()
            didChangeText()
            undoManager?.endUndoGrouping()
            setSelectedRange(NSRange(location: lineRange.location, length: (finalText as NSString).length))
        }
    }

    func unindentSelection() {
        let range = selectedRange()
        let text = string as NSString
        let lineRange = text.lineRange(for: range)
        let selectedText = text.substring(with: lineRange)
        var lines = selectedText.components(separatedBy: "\n")

        if lines.last == "" { lines.removeLast() }

        let unindented = lines.map { stripLeadingIndent(from: $0) }.joined(separator: "\n")

        let finalText = selectedText.hasSuffix("\n") ? unindented + "\n" : unindented

        if shouldChangeText(in: lineRange, replacementString: finalText) {
            undoManager?.beginUndoGrouping()
            textStorage?.beginEditing()
            textStorage?.replaceCharacters(in: lineRange, with: finalText)
            textStorage?.endEditing()
            didChangeText()
            undoManager?.endUndoGrouping()
            setSelectedRange(NSRange(location: lineRange.location, length: (finalText as NSString).length))
        }
    }

    /// Comments out the selected lines with `%%`, or uncomments them when all are comments.
    @objc func toggleComment(_ sender: Any?) {
        let selection = selectedRange()
        let text = string as NSString
        let lineRange = text.lineRange(for: selection)
        let block = text.substring(with: lineRange)
        var lines = block.components(separatedBy: "\n")
        if block.hasSuffix("\n") { lines.removeLast() }

        let contentLines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let targets = contentLines.isEmpty ? lines : contentLines
        let isCommented = { (line: String) in
            let code = line.drop { $0 == " " || $0 == "\t" }
            // `%%{...}%%` is a directive, not a comment
            return code.hasPrefix("%%") && !code.hasPrefix("%%{")
        }

        let toggled: [String]
        if targets.allSatisfy(isCommented) {
            toggled = lines.map { line in
                guard isCommented(line), let marker = line.range(of: "%%") else { return line }
                var end = marker.upperBound
                if end < line.endIndex, line[end] == " " { end = line.index(after: end) }
                return line.replacingCharacters(in: marker.lowerBound..<end, with: "")
            }
        } else {
            let indent = targets.map { $0.prefix { $0 == " " || $0 == "\t" }.count }.min() ?? 0
            toggled = lines.map { line in
                guard contentLines.isEmpty || !line.trimmingCharacters(in: .whitespaces).isEmpty else { return line }
                let insertion = line.index(line.startIndex, offsetBy: min(indent, line.count))
                return line.replacingCharacters(in: insertion..<insertion, with: "%% ")
            }
        }

        let joined = toggled.joined(separator: "\n")
        let replacement = block.hasSuffix("\n") ? joined + "\n" : joined
        guard replacement != block, shouldChangeText(in: lineRange, replacementString: replacement) else { return }
        textStorage?.replaceCharacters(in: lineRange, with: replacement)
        didChangeText()

        let replacementLength = (replacement as NSString).length
        if selection.length == 0, lines.count == 1 {
            let shifted = selection.location + replacementLength - lineRange.length
            setSelectedRange(NSRange(location: max(lineRange.location, shifted), length: 0))
        } else {
            setSelectedRange(NSRange(location: lineRange.location, length: replacementLength))
        }
    }

    private func stripLeadingIndent(from line: String) -> String {
        if line.hasPrefix(MermaidIndentation.unit) {
            return String(line.dropFirst(MermaidIndentation.unit.count))
        } else if line.hasPrefix("\t") {
            return String(line.dropFirst(1))
        }
        let stripped = line.drop(while: { $0 == " " })
        return stripped.isEmpty ? line : String(stripped)
    }

    override func insertTab(_ sender: Any?) {
        guard activeCompletions == nil else {
            acceptCompletion()
            return
        }
        indentSelection()
    }

    override func insertBacktab(_ sender: Any?) {
        unindentSelection()
    }

    override func insertNewline(_ sender: Any?) {
        guard activeCompletions == nil else {
            acceptCompletion()
            return
        }
        insertNewlineWithIndent()
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        super.insertText(string, replacementRange: replacementRange)
        let typed = (string as? String) ?? (string as? NSAttributedString)?.string
        if let typed {
            showCompletions(afterTyping: typed)
        }
        guard typed == " " || typed == "}",
            let realignment = MermaidIndentation.realignment(
                afterTypingIn: self.string as NSString, at: selectedRange().location)
        else { return }
        breakUndoCoalescing()
        apply(realignment)
        breakUndoCoalescing()
    }

    private func insertNewlineWithIndent() {
        let newline = MermaidIndentation.newline(in: string as NSString, at: selectedRange().location)
        guard let realignment = newline.realignment else {
            insertText("\n" + newline.indent, replacementRange: selectedRange())
            return
        }
        // one undo step covers the realignment and the newline
        breakUndoCoalescing()
        apply(realignment)
        insertText("\n" + newline.indent, replacementRange: selectedRange())
        breakUndoCoalescing()
    }

    private func apply(_ realignment: MermaidIndentation.Realignment) {
        let selection = selectedRange()
        guard shouldChangeText(in: realignment.range, replacementString: realignment.indent) else { return }
        textStorage?.replaceCharacters(in: realignment.range, with: realignment.indent)
        didChangeText()
        let shift = realignment.indent.utf16.count - realignment.range.length
        setSelectedRange(NSRange(location: selection.location + shift, length: selection.length))
    }
}
