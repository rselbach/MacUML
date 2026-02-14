import AppKit

extension CodeTextView {
    private enum KeyCode: UInt16 {
        case tab = 48
        case returnKey = 36
        case home = 115
        case end = 119
        case pageUp = 116
        case pageDown = 121
        case leftArrow = 123
        case rightArrow = 124
        case upArrow = 126
        case downArrow = 125
    }

    func handleKeyDown(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasShift = flags.contains(.shift)

        switch event.keyCode {
        case KeyCode.tab.rawValue:
            if hasShift {
                unindentSelection()
            } else {
                indentSelection()
            }
            return true
        case KeyCode.returnKey.rawValue:
            insertNewlineWithIndent()
            return true
        case KeyCode.home.rawValue:
            if hasShift {
                moveToBeginningOfLineAndModifySelection(nil)
            } else {
                moveToBeginningOfLine(nil)
            }
            return true
        case KeyCode.end.rawValue:
            if hasShift {
                moveToEndOfLineAndModifySelection(nil)
            } else {
                moveToEndOfLine(nil)
            }
            return true
        case KeyCode.pageUp.rawValue:
            if hasShift {
                pageUpAndModifySelection(nil)
            } else {
                pageUp(nil)
            }
            return true
        case KeyCode.pageDown.rawValue:
            if hasShift {
                pageDownAndModifySelection(nil)
            } else {
                pageDown(nil)
            }
            return true
        case KeyCode.leftArrow.rawValue:
            if flags.contains(.command) {
                if hasShift {
                    moveToBeginningOfLineAndModifySelection(nil)
                } else {
                    moveToBeginningOfLine(nil)
                }
                return true
            }
        case KeyCode.rightArrow.rawValue:
            if flags.contains(.command) {
                if hasShift {
                    moveToEndOfLineAndModifySelection(nil)
                } else {
                    moveToEndOfLine(nil)
                }
                return true
            }
        case KeyCode.upArrow.rawValue:
            if flags.contains(.command) {
                if hasShift {
                    moveToBeginningOfDocumentAndModifySelection(nil)
                } else {
                    moveToBeginningOfDocument(nil)
                }
                return true
            }
        case KeyCode.downArrow.rawValue:
            if flags.contains(.command) {
                if hasShift {
                    moveToEndOfDocumentAndModifySelection(nil)
                } else {
                    moveToEndOfDocument(nil)
                }
                return true
            }
        default:
            break
        }
        return false
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
            replaceCharacters(in: lineRange, with: finalText)
            didChangeText()
            setSelectedRange(NSRange(location: lineRange.location, length: finalText.count))
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
            replaceCharacters(in: lineRange, with: finalText)
            didChangeText()
            setSelectedRange(NSRange(location: lineRange.location, length: finalText.count))
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
