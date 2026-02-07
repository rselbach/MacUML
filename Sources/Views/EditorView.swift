import SwiftUI
import AppKit

final class CodeTextView: NSTextView {
    static let indentString = "    "
    private let highlighter = MermaidHighlighter.shared
    private var highlightWorkItem: DispatchWorkItem?
    private var pendingHighlightRange: NSRange?
    private var errorLine: Int?

    override func didChangeText() {
        super.didChangeText()
        scheduleHighlighting(editedRange: textStorage?.editedRange)
    }

    private func scheduleHighlighting(editedRange: NSRange? = nil) {
        if let editedRange,
           editedRange.location != NSNotFound {
            if let pendingRange = pendingHighlightRange {
                pendingHighlightRange = NSUnionRange(pendingRange, editedRange)
            } else {
                pendingHighlightRange = editedRange
            }
        }

        highlightWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, let storage = self.textStorage else { return }
            self.highlighter.highlight(storage, in: self.pendingHighlightRange)
            self.pendingHighlightRange = nil
            self.applyErrorHighlighting()
        }
        highlightWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: workItem)
    }

    func applyInitialHighlighting() {
        guard let storage = textStorage else { return }
        highlighter.highlight(storage)
        applyErrorHighlighting()
    }
    
    func setErrorLine(_ line: Int?) {
        guard errorLine != line else { return }
        errorLine = line
        applyErrorHighlighting()
    }
    
    private func applyErrorHighlighting() {
        guard let storage = textStorage else { return }
        let text = storage.string as NSString
        let fullRange = NSRange(location: 0, length: storage.length)
        
        storage.removeAttribute(.underlineStyle, range: fullRange)
        storage.removeAttribute(.underlineColor, range: fullRange)
        storage.removeAttribute(.backgroundColor, range: fullRange)
        
        guard let errorLine, errorLine > 0 else { return }
        
        var currentLine = 1
        var lineStart = 0
        
        while currentLine < errorLine && lineStart < text.length {
            let lineRange = text.lineRange(for: NSRange(location: lineStart, length: 0))
            lineStart = lineRange.upperBound
            currentLine += 1
        }
        
        if currentLine == errorLine && lineStart < text.length {
            let lineRange = text.lineRange(for: NSRange(location: lineStart, length: 0))
            storage.addAttribute(.backgroundColor, value: NSColor.systemRed.withAlphaComponent(0.2), range: lineRange)
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: lineRange)
            storage.addAttribute(.underlineColor, value: NSColor.systemRed, range: lineRange)
        }
    }
    
    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasShift = flags.contains(.shift)
        
        switch event.keyCode {
        case 48: // Tab
            if hasShift {
                unindentSelection()
            } else {
                indentSelection()
            }
        case 36: // Return/Enter
            insertNewlineWithIndent()
        case 115: // Home
            if hasShift {
                moveToBeginningOfLineAndModifySelection(nil)
            } else {
                moveToBeginningOfLine(nil)
            }
        case 119: // End
            if hasShift {
                moveToEndOfLineAndModifySelection(nil)
            } else {
                moveToEndOfLine(nil)
            }
        case 116: // Page Up
            if hasShift {
                pageUpAndModifySelection(nil)
            } else {
                pageUp(nil)
            }
        case 121: // Page Down
            if hasShift {
                pageDownAndModifySelection(nil)
            } else {
                pageDown(nil)
            }
        case 123: // Left Arrow
            if flags.contains(.command) {
                if hasShift {
                    moveToBeginningOfLineAndModifySelection(nil)
                } else {
                    moveToBeginningOfLine(nil)
                }
            } else {
                super.keyDown(with: event)
            }
        case 124: // Right Arrow
            if flags.contains(.command) {
                if hasShift {
                    moveToEndOfLineAndModifySelection(nil)
                } else {
                    moveToEndOfLine(nil)
                }
            } else {
                super.keyDown(with: event)
            }
        case 126: // Up Arrow
            if flags.contains(.command) {
                if hasShift {
                    moveToBeginningOfDocumentAndModifySelection(nil)
                } else {
                    moveToBeginningOfDocument(nil)
                }
            } else {
                super.keyDown(with: event)
            }
        case 125: // Down Arrow
            if flags.contains(.command) {
                if hasShift {
                    moveToEndOfDocumentAndModifySelection(nil)
                } else {
                    moveToEndOfDocument(nil)
                }
            } else {
                super.keyDown(with: event)
            }
        default:
            super.keyDown(with: event)
        }
    }
    
    private func indentSelection() {
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
    
    private func unindentSelection() {
        let range = selectedRange()
        let text = string as NSString
        let lineRange = text.lineRange(for: range)
        var lines = text.substring(with: lineRange).components(separatedBy: "\n")
        
        if lines.last == "" { lines.removeLast() }
        
        let unindented = lines.map { line -> String in
            if line.hasPrefix(Self.indentString) {
                return String(line.dropFirst(Self.indentString.count))
            } else if line.hasPrefix("\t") {
                return String(line.dropFirst(1))
            }
            return line.drop(while: { $0 == " " }).description.isEmpty ? line : String(line.drop(while: { $0 == " " }))
        }.joined(separator: "\n")
        
        let finalText = lineRange.upperBound < text.length ? unindented + "\n" : unindented
        
        if shouldChangeText(in: lineRange, replacementString: finalText) {
            replaceCharacters(in: lineRange, with: finalText)
            didChangeText()
            setSelectedRange(NSRange(location: lineRange.location, length: finalText.count))
        }
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

struct EditorView: NSViewRepresentable {
    @Binding var text: String
    var errorLine: Int?
    @ObservedObject private var settings = AppSettings.shared

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = CodeTextView()
        
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true

        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.font = settings.editorFont
        textView.textColor = NSColor.textColor
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.allowsUndo = true
        textView.usesFindBar = true

        textView.string = text
        textView.applyInitialHighlighting()
        
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? CodeTextView else { return }
        
        textView.font = settings.editorFont
        
        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selectedRanges
            textView.applyInitialHighlighting()
        }
        textView.setErrorLine(errorLine)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}
