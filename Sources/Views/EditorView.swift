import SwiftUI
import AppKit

final class CodeTextView: NSTextView {
    static let indentString = "    "
    private static let highlightDebounceInterval: TimeInterval = 0.1
    private let highlighter = MermaidHighlighter.shared
    private var highlightWorkItem: DispatchWorkItem?
    private var pendingHighlightRange: NSRange?
    private var errorLine: Int?
    private var previousErrorRange: NSRange?

    override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
        let allowed = super.shouldChangeText(in: affectedCharRange, replacementString: replacementString)
        guard allowed else {
            return false
        }

        if let rulerView = enclosingScrollView?.verticalRulerView as? LineNumberRulerView {
            let currentText = string as NSString
            if affectedCharRange.location != NSNotFound,
               affectedCharRange.location <= currentText.length {
                let safeLength = min(affectedCharRange.length, currentText.length - affectedCharRange.location)
                let safeRange = NSRange(location: affectedCharRange.location, length: safeLength)
                let removedNewlines = newlineCount(in: currentText.substring(with: safeRange))
                let insertedNewlines = newlineCount(in: replacementString ?? "")
                rulerView.applyLineDelta(insertedNewlines - removedNewlines)
            }
        }

        return true
    }

    override func didChangeText() {
        super.didChangeText()
        queueIncrementalHighlightRange()
        scheduleHighlighting()
    }

    private func scheduleHighlighting() {
        highlightWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, let storage = self.textStorage else { return }
            let range = self.pendingHighlightRange
            self.pendingHighlightRange = nil
            Task { @MainActor [weak self] in
                await self?.highlighter.highlight(storage, in: range)
                self?.applyErrorHighlighting()
            }
        }
        highlightWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.highlightDebounceInterval, execute: workItem)
    }

    func applyInitialHighlighting() {
        guard let storage = textStorage else { return }
        pendingHighlightRange = nil
        Task { @MainActor [weak self] in
            await self?.highlighter.highlight(storage)
            self?.applyErrorHighlighting()
        }
    }

    private func queueIncrementalHighlightRange() {
        guard let storage = textStorage else { return }
        let editedRange = storage.editedRange
        guard editedRange.location != NSNotFound,
              editedRange.location <= storage.length else {
            return
        }

        let text = storage.string as NSString
        let safeLength = min(editedRange.length, max(0, text.length - editedRange.location))
        var range = NSRange(location: editedRange.location, length: safeLength)
        range = text.lineRange(for: range)

        if range.location > 0 {
            range = text.lineRange(for: NSRange(location: range.location - 1, length: range.length + 1))
        }
        if NSMaxRange(range) < text.length {
            range = text.lineRange(for: NSRange(location: range.location, length: range.length + 1))
        }

        if let pendingHighlightRange {
            self.pendingHighlightRange = NSUnionRange(pendingHighlightRange, range)
            return
        }

        pendingHighlightRange = range
    }

    private func newlineCount(in value: String) -> Int {
        value.reduce(into: 0) { count, char in
            if char == "\n" {
                count += 1
            }
        }
    }
    
    func setErrorLine(_ line: Int?) {
        guard errorLine != line else { return }
        errorLine = line
        applyErrorHighlighting()
    }
    
    private func applyErrorHighlighting() {
        guard let storage = textStorage else { return }
        let text = storage.string as NSString

        if let previousErrorRange {
            removeErrorAttributes(in: previousErrorRange, storage: storage)
            self.previousErrorRange = nil
        }

        guard let errorLine, let range = lineRange(for: errorLine, in: text) else { return }

        storage.addAttribute(.backgroundColor, value: NSColor.systemRed.withAlphaComponent(0.2), range: range)
        storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        storage.addAttribute(.underlineColor, value: NSColor.systemRed, range: range)
        previousErrorRange = range
    }

    private func removeErrorAttributes(in range: NSRange, storage: NSTextStorage) {
        guard let clampedRange = clampedRange(range, maxLength: storage.length) else { return }
        storage.removeAttribute(.underlineStyle, range: clampedRange)
        storage.removeAttribute(.underlineColor, range: clampedRange)
        storage.removeAttribute(.backgroundColor, range: clampedRange)
    }

    private func clampedRange(_ range: NSRange, maxLength: Int) -> NSRange? {
        guard maxLength > 0,
              range.location != NSNotFound,
              range.location < maxLength else {
            return nil
        }

        let documentRange = NSRange(location: 0, length: maxLength)
        let clampedRange = NSIntersectionRange(range, documentRange)
        guard clampedRange.length > 0 else {
            return nil
        }

        return clampedRange
    }

    private func lineRange(for oneBasedLine: Int, in text: NSString) -> NSRange? {
        guard oneBasedLine > 0 else {
            return nil
        }

        var currentLine = 1
        var lineStart = 0

        while currentLine < oneBasedLine && lineStart < text.length {
            let currentRange = text.lineRange(for: NSRange(location: lineStart, length: 0))
            lineStart = currentRange.upperBound
            currentLine += 1
        }

        guard currentLine == oneBasedLine,
              lineStart < text.length else {
            return nil
        }

        return text.lineRange(for: NSRange(location: lineStart, length: 0))
    }
    
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

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasShift = flags.contains(.shift)
        
        switch event.keyCode {
        case KeyCode.tab.rawValue:
            if hasShift {
                unindentSelection()
            } else {
                indentSelection()
            }
        case KeyCode.returnKey.rawValue:
            insertNewlineWithIndent()
        case KeyCode.home.rawValue:
            if hasShift {
                moveToBeginningOfLineAndModifySelection(nil)
            } else {
                moveToBeginningOfLine(nil)
            }
        case KeyCode.end.rawValue:
            if hasShift {
                moveToEndOfLineAndModifySelection(nil)
            } else {
                moveToEndOfLine(nil)
            }
        case KeyCode.pageUp.rawValue:
            if hasShift {
                pageUpAndModifySelection(nil)
            } else {
                pageUp(nil)
            }
        case KeyCode.pageDown.rawValue:
            if hasShift {
                pageDownAndModifySelection(nil)
            } else {
                pageDown(nil)
            }
        case KeyCode.leftArrow.rawValue:
            if flags.contains(.command) {
                if hasShift {
                    moveToBeginningOfLineAndModifySelection(nil)
                } else {
                    moveToBeginningOfLine(nil)
                }
            } else {
                super.keyDown(with: event)
            }
        case KeyCode.rightArrow.rawValue:
            if flags.contains(.command) {
                if hasShift {
                    moveToEndOfLineAndModifySelection(nil)
                } else {
                    moveToEndOfLine(nil)
                }
            } else {
                super.keyDown(with: event)
            }
        case KeyCode.upArrow.rawValue:
            if flags.contains(.command) {
                if hasShift {
                    moveToBeginningOfDocumentAndModifySelection(nil)
                } else {
                    moveToBeginningOfDocument(nil)
                }
            } else {
                super.keyDown(with: event)
            }
        case KeyCode.downArrow.rawValue:
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
        textView.font = AppSettings.shared.editorFont
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
        scrollView.verticalRulerView = LineNumberRulerView(textView: textView)
        scrollView.hasVerticalRuler = AppSettings.shared.showLineNumbers
        scrollView.rulersVisible = AppSettings.shared.showLineNumbers

        if let rulerView = scrollView.verticalRulerView as? LineNumberRulerView {
            rulerView.refresh(using: AppSettings.shared.editorFont)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? CodeTextView else { return }
        let settings = AppSettings.shared
        let fontChanged = textView.font != settings.editorFont
        if fontChanged {
            textView.font = settings.editorFont
        }

        if textView.string != text {
            let previousRanges = textView.selectedRanges
            let newText = text as NSString
            textView.string = text
            textView.selectedRanges = previousRanges.map { rangeValue in
                guard let range = rangeValue as? NSRange else { return rangeValue }
                let clampedLocation = min(range.location, newText.length)
                let clampedLength = min(range.length, max(0, newText.length - clampedLocation))
                return NSRange(location: clampedLocation, length: clampedLength) as NSValue
            }
            textView.applyInitialHighlighting()

            if let rulerView = scrollView.verticalRulerView as? LineNumberRulerView {
                rulerView.resetLineCount(using: text)
            }
        }

        if scrollView.hasVerticalRuler != settings.showLineNumbers {
            scrollView.hasVerticalRuler = settings.showLineNumbers
        }
        if scrollView.rulersVisible != settings.showLineNumbers {
            scrollView.rulersVisible = settings.showLineNumbers
        }

        if fontChanged, let rulerView = scrollView.verticalRulerView as? LineNumberRulerView {
            rulerView.refresh(using: settings.editorFont)
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
