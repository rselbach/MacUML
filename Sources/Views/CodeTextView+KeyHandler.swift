import AppKit
import Carbon.HIToolbox.Events

extension CodeTextView {
    private enum KeyCode: UInt16 {
        case tab
        case returnKey
        case home
        case end
        case pageUp
        case pageDown
        case leftArrow
        case rightArrow
        case upArrow
        case downArrow
        case s

        init?(rawValue: UInt16) {
            switch Int(rawValue) {
            case kVK_Tab: self = .tab
            case kVK_Return: self = .returnKey
            case kVK_Home: self = .home
            case kVK_End: self = .end
            case kVK_PageUp: self = .pageUp
            case kVK_PageDown: self = .pageDown
            case kVK_LeftArrow: self = .leftArrow
            case kVK_RightArrow: self = .rightArrow
            case kVK_UpArrow: self = .upArrow
            case kVK_DownArrow: self = .downArrow
            case kVK_ANSI_S: self = .s
            default: return nil
            }
        }
    }

    func handleKeyDown(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasShift = flags.contains(.shift)
        let hasCommand = flags.contains(.command)

        // Handle Cmd+S for auto-format on save
        if hasCommand, !hasShift, event.keyCode == UInt16(kVK_ANSI_S) {
            if AppSettings.shared.autoFormatOnSave {
                onFormatRequest?()
                // Return false to let the save proceed after formatting
            }
            return false
        }

        guard let keyCode = KeyCode(rawValue: event.keyCode) else {
            return false
        }

        switch keyCode {
        case .tab:
            if hasShift {
                unindentSelection()
            } else {
                indentSelection()
            }
            return true
        case .returnKey:
            insertNewlineWithIndent()
            return true
        case .home:
            performMove(hasShift: hasShift, normal: #selector(moveToBeginningOfLine(_:)), modify: #selector(moveToBeginningOfLineAndModifySelection(_:)))
            return true
        case .end:
            performMove(hasShift: hasShift, normal: #selector(moveToEndOfLine(_:)), modify: #selector(moveToEndOfLineAndModifySelection(_:)))
            return true
        case .pageUp:
            performMove(hasShift: hasShift, normal: #selector(pageUp(_:)), modify: #selector(pageUpAndModifySelection(_:)))
            return true
        case .pageDown:
            performMove(hasShift: hasShift, normal: #selector(pageDown(_:)), modify: #selector(pageDownAndModifySelection(_:)))
            return true
        case .leftArrow:
            if flags.contains(.option) {
                performMove(hasShift: hasShift, normal: #selector(moveWordBackward(_:)), modify: #selector(moveWordBackwardAndModifySelection(_:)))
                return true
            }
        case .rightArrow:
            if flags.contains(.option) {
                performMove(hasShift: hasShift, normal: #selector(moveWordForward(_:)), modify: #selector(moveWordForwardAndModifySelection(_:)))
                return true
            }
        case .upArrow:
            if flags.contains(.option) {
                performMove(hasShift: hasShift, normal: #selector(moveToBeginningOfParagraph(_:)), modify: #selector(moveToBeginningOfParagraphAndModifySelection(_:)))
                return true
            }
        case .downArrow:
            if flags.contains(.command) {
                performMove(hasShift: hasShift, normal: #selector(moveToEndOfDocument(_:)), modify: #selector(moveToEndOfDocumentAndModifySelection(_:)))
                return true
            }
        case .s:
            // Cmd+S is handled earlier; this handles plain 's' key
            return false
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
            insertText(Self.indentString, replacementRange: range)
            return
        }

        let lineRange = text.lineRange(for: range)
        var lines = text.substring(with: lineRange).components(separatedBy: "\n")

        if lines.last == "" { lines.removeLast() }

        let indented = lines.map { Self.indentString + $0 }.joined(separator: "\n")
        let finalText = lineRange.upperBound < text.length ? indented + "\n" : indented

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
        var lines = text.substring(with: lineRange).components(separatedBy: "\n")

        if lines.last == "" { lines.removeLast() }

        let unindented = lines.map { stripLeadingIndent(from: $0) }.joined(separator: "\n")

        let finalText = lineRange.upperBound < text.length ? unindented + "\n" : unindented

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

    private func stripLeadingIndent(from line: String) -> String {
        if line.hasPrefix(Self.indentString) {
            return String(line.dropFirst(Self.indentString.count))
        } else if line.hasPrefix("\t") {
            return String(line.dropFirst(1))
        }
        let stripped = line.drop(while: { $0 == " " })
        return stripped.isEmpty ? line : String(stripped)
    }

    private func insertNewlineWithIndent() {
        let text = string as NSString
        let cursorLocation = selectedRange().location
        let lineStart = text.lineRange(for: NSRange(location: cursorLocation, length: 0)).location
        let linePrefix = text.substring(with: NSRange(location: lineStart, length: cursorLocation - lineStart))

        let indent = String(linePrefix.prefix(while: { $0 == " " || $0 == "\t" }))
        insertText("\n" + indent, replacementRange: selectedRange())
    }
}
