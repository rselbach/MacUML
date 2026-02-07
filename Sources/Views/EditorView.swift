import SwiftUI
import AppKit

final class CodeTextView: NSTextView {
    static let indentString = "    "
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
            self.highlighter.highlight(storage, in: range)
            self.applyErrorHighlighting()
        }
        highlightWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: workItem)
    }

    func applyInitialHighlighting() {
        guard let storage = textStorage else { return }
        pendingHighlightRange = nil
        highlighter.highlight(storage)
        applyErrorHighlighting()
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

final class LineNumberRulerView: NSRulerView {
    private weak var textView: NSTextView?
    private var lineNumberAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
        .foregroundColor: NSColor.secondaryLabelColor
    ]

    private let minThickness: CGFloat = 36
    private let horizontalPadding: CGFloat = 8
    private var cachedLineCount = 1
    private var lineStartOffsets: [Int] = [0]

    init(textView: NSTextView) {
        guard let scrollView = textView.enclosingScrollView else {
            fatalError("LineNumberRulerView requires a text view in a scroll view")
        }

        self.textView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        rebuildLineMetadata(using: textView.string)
        configureObservers()
        recalculateThickness()
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func refresh(using editorFont: NSFont) {
        let newFont = NSFont.monospacedDigitSystemFont(ofSize: max(10, editorFont.pointSize * 0.85), weight: .regular)
        let oldFont = lineNumberAttributes[.font] as? NSFont
        guard oldFont?.pointSize != newFont.pointSize else {
            return
        }

        lineNumberAttributes = [
            .font: newFont,
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        recalculateThickness()
        needsDisplay = true
    }

    func resetLineCount(using text: String) {
        rebuildLineMetadata(using: text)
        recalculateThickness()
        needsDisplay = true
    }

    func applyLineDelta(_ delta: Int) {
        guard delta != 0 else {
            return
        }

        let oldDigits = String(max(1, cachedLineCount)).count
        cachedLineCount = max(1, cachedLineCount + delta)
        let newDigits = String(max(1, cachedLineCount)).count

        if oldDigits != newDigits {
            recalculateThickness()
        }

        needsDisplay = true
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        NSColor.controlBackgroundColor.setFill()
        bounds.fill()

        let separatorX = bounds.maxX - 0.5
        NSColor.separatorColor.withAlphaComponent(0.6).setStroke()
        let separator = NSBezierPath()
        separator.move(to: NSPoint(x: separatorX, y: bounds.minY))
        separator.line(to: NSPoint(x: separatorX, y: bounds.maxY))
        separator.stroke()

        let visibleRect = scrollView?.contentView.bounds ?? rect
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let text = textView.string as NSString

        if text.length == 0 {
            draw(lineNumber: 1, atY: textView.textContainerInset.height)
            return
        }

        let firstVisibleLine = lineNumber(for: glyphRange.location, layoutManager: layoutManager)
        var currentLine = firstVisibleLine
        var lastLineLocation = NSNotFound
        let rulerOffset = convert(.zero, from: textView).y

        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, usedRect, _, fragmentGlyphRange, _ in
            let charRange = layoutManager.characterRange(forGlyphRange: fragmentGlyphRange, actualGlyphRange: nil)
            let lineRange = text.lineRange(for: NSRange(location: charRange.location, length: 0))

            guard lineRange.location != lastLineLocation else { return }

            lastLineLocation = lineRange.location
            let lineY = usedRect.minY + textView.textContainerInset.height + rulerOffset
            self.draw(lineNumber: currentLine, atY: lineY)
            currentLine += 1
        }
    }

    private func configureObservers() {
        guard let textView else { return }

        if let contentView = scrollView?.contentView {
            contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleBoundsChanged(_:)),
                name: NSView.boundsDidChangeNotification,
                object: contentView
            )
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTextChanged(_:)),
            name: NSText.didChangeNotification,
            object: textView
        )
    }

    @objc
    private func handleBoundsChanged(_ notification: Notification) {
        needsDisplay = true
    }

    @objc
    private func handleTextChanged(_ notification: Notification) {
        if let textView = notification.object as? NSTextView {
            rebuildLineMetadata(using: textView.string)
            recalculateThickness()
        }
        needsDisplay = true
    }

    private func recalculateThickness() {
        let digits = String(max(1, cachedLineCount)).count
        let sample = String(repeating: "8", count: digits) as NSString
        let labelWidth = sample.size(withAttributes: lineNumberAttributes).width
        let targetThickness = max(minThickness, ceil(labelWidth + (horizontalPadding * 2)))

        if abs(ruleThickness - targetThickness) > .ulpOfOne {
            ruleThickness = targetThickness
        }
    }

    private func lineNumber(for glyphLocation: Int, layoutManager: NSLayoutManager) -> Int {
        guard layoutManager.numberOfGlyphs > 0 else { return 1 }

        let glyphIndex = min(max(glyphLocation, 0), layoutManager.numberOfGlyphs - 1)
        let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)

        guard charIndex > 0 else { return 1 }

        var low = 0
        var high = lineStartOffsets.count

        while low < high {
            let mid = (low + high) / 2
            if lineStartOffsets[mid] <= charIndex {
                low = mid + 1
                continue
            }
            high = mid
        }

        return max(1, low)
    }

    private func rebuildLineMetadata(using text: String) {
        lineStartOffsets = [0]
        if text.isEmpty {
            cachedLineCount = 1
            return
        }

        let nsText = text as NSString
        var location = 0

        while location < nsText.length {
            let lineRange = nsText.lineRange(for: NSRange(location: location, length: 0))
            let nextLineStart = NSMaxRange(lineRange)
            if nextLineStart < nsText.length {
                lineStartOffsets.append(nextLineStart)
            }
            location = nextLineStart
        }

        cachedLineCount = max(1, lineStartOffsets.count)
    }

    private func draw(lineNumber: Int, atY y: CGFloat) {
        let label = "\(lineNumber)" as NSString
        let size = label.size(withAttributes: lineNumberAttributes)
        let x = ruleThickness - horizontalPadding - size.width
        label.draw(at: NSPoint(x: x, y: y + 1), withAttributes: lineNumberAttributes)
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
        scrollView.verticalRulerView = LineNumberRulerView(textView: textView)
        scrollView.hasVerticalRuler = settings.showLineNumbers
        scrollView.rulersVisible = settings.showLineNumbers

        if let rulerView = scrollView.verticalRulerView as? LineNumberRulerView {
            rulerView.refresh(using: settings.editorFont)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? CodeTextView else { return }
        let fontChanged = textView.font != settings.editorFont
        if fontChanged {
            textView.font = settings.editorFont
        }
        
        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selectedRanges
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
