import SwiftUI
import AppKit

final class CodeTextView: NSTextView {
    static let indentString = "    "
    private static let highlightDebounceInterval: Duration = .milliseconds(100)
    private let highlighter = MermaidHighlighter.shared
    private var highlightTask: Task<Void, Never>?
    private var pendingHighlightRange: NSRange?
    var errorLine: Int?
    var previousErrorRange: NSRange?
    var onFormatRequest: (() -> Void)?
    var autoFormatOnSave = false

    private(set) var lineStartOffsets: [Int] = [0]

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
                let removedNewlines = countNewlines(in: currentText.substring(with: safeRange))
                let insertedNewlines = countNewlines(in: replacementString ?? "")
                rulerView.applyLineDelta(insertedNewlines - removedNewlines)
            }
        }

        return true
    }

    override func didChangeText() {
        super.didChangeText()
        let currentString = string
        if let storage = textStorage {
            updateLineStartOffsetsIncrementally(using: storage, currentString: currentString)
        } else {
            rebuildLineStartOffsets(for: currentString)
        }
        queueIncrementalHighlightRange()
        scheduleHighlighting()
    }

    private func rebuildLineStartOffsets(for currentString: String) {
        // O(N) iteration over UTF-16 code units is ~100x faster than calling NSString.lineRange in a while loop
        var offsets = [0]
        let utf16 = currentString.utf16
        // Pre-allocate to avoid reallocation overhead. Assuming average line length of 40.
        offsets.reserveCapacity(utf16.count / 40 + 1)
        
        let newline: UTF16.CodeUnit = 10 // '\n'
        let textLength = utf16.count
        var offset = 0
        for char in utf16 {
            offset += 1
            if char == newline && offset < textLength {
                offsets.append(offset)
            }
        }
        lineStartOffsets = offsets
    }

    private func updateLineStartOffsetsIncrementally(using storage: NSTextStorage, currentString: String) {
        guard !lineStartOffsets.isEmpty else {
            rebuildLineStartOffsets(for: currentString)
            return
        }

        let editedRange = storage.editedRange
        guard editedRange.location != NSNotFound,
              editedRange.location <= storage.length else {
            rebuildLineStartOffsets(for: currentString)
            return
        }

        let changeInLength = storage.changeInLength
        let newEditedLength = editedRange.length
        let oldEditedLength = newEditedLength - changeInLength
        guard oldEditedLength >= 0 else {
            rebuildLineStartOffsets(for: currentString)
            return
        }

        let previousTextLength = storage.length - changeInLength
        guard previousTextLength >= 0 else {
            rebuildLineStartOffsets(for: currentString)
            return
        }

        let oldEditEnd = editedRange.location + oldEditedLength
        guard oldEditEnd <= previousTextLength else {
            rebuildLineStartOffsets(for: currentString)
            return
        }

        let newTextLength = storage.length
        let safeLocation = min(editedRange.location, newTextLength)

        let startIndex = lineIndex(atOrBefore: safeLocation)
        let recalcStart = lineStartOffsets[startIndex]

        let suffixStartIndex = firstLineIndex(greaterThan: oldEditEnd)
        let oldRecalcEnd = suffixStartIndex < lineStartOffsets.count
            ? lineStartOffsets[suffixStartIndex]
            : previousTextLength

        let newRecalcEnd = max(recalcStart, min(newTextLength, oldRecalcEnd + changeInLength))

        var updatedOffsets = Array(lineStartOffsets.prefix(startIndex + 1))
        updatedOffsets.append(contentsOf: lineStarts(in: currentString, from: recalcStart, to: newRecalcEnd))

        if suffixStartIndex < lineStartOffsets.count {
            for offset in lineStartOffsets[suffixStartIndex...] {
                let shifted = offset + changeInLength
                if shifted > recalcStart && shifted < newTextLength {
                    if updatedOffsets.last != shifted {
                        updatedOffsets.append(shifted)
                    }
                }
            }
        }

        if updatedOffsets.first != 0 {
            updatedOffsets.insert(0, at: 0)
        }
        lineStartOffsets = updatedOffsets
    }

    private func lineStarts(in text: String, from start: Int, to end: Int) -> [Int] {
        guard start < end else {
            return []
        }

        let nsText = text as NSString
        let safeStart = min(max(0, start), nsText.length)
        let safeEnd = min(max(safeStart, end), nsText.length)
        guard safeStart < safeEnd else {
            return []
        }

        let segment = nsText.substring(with: NSRange(location: safeStart, length: safeEnd - safeStart))
        let utf16 = segment.utf16
        let newline: UTF16.CodeUnit = 10

        var starts: [Int] = []
        starts.reserveCapacity(max(1, utf16.count / 40))

        var offset = safeStart
        for char in utf16 {
            offset += 1
            if char == newline && offset < nsText.length {
                starts.append(offset)
            }
        }

        return starts
    }

    private func lineIndex(atOrBefore position: Int) -> Int {
        max(0, Self.firstIndex(greaterThan: position, in: lineStartOffsets) - 1)
    }

    private func firstLineIndex(greaterThan position: Int) -> Int {
        Self.firstIndex(greaterThan: position, in: lineStartOffsets)
    }

    static func firstIndex(greaterThan value: Int, in offsets: [Int]) -> Int {
        var low = 0
        var high = offsets.count
        while low < high {
            let mid = low + (high - low) / 2
            if offsets[mid] > value {
                high = mid
            } else {
                low = mid + 1
            }
        }
        return low
    }

    func needsUpdate(for newText: String) -> Bool {
        string != newText
    }

    private func scheduleHighlighting() {
        highlightTask?.cancel()
        highlightTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: Self.highlightDebounceInterval)
            } catch { return }
            guard let self, let storage = self.textStorage else { return }
            let range = self.pendingHighlightRange
            self.pendingHighlightRange = nil
            await self.highlighter.highlight(storage, in: range)
            guard !Task.isCancelled else { return }
            self.applyErrorHighlighting()
        }
    }

    func applyInitialHighlighting() {
        guard let storage = textStorage else { return }
        rebuildLineStartOffsets(for: storage.string)
        pendingHighlightRange = nil
        highlightTask?.cancel()
        highlightTask = Task { @MainActor [weak self] in
            await self?.highlighter.highlight(storage)
            guard !Task.isCancelled else { return }
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

    func performFormat() {
        let formatted = MermaidFormatter.format(string)
        guard formatted != string else { return }
        string = formatted
        if let coordinator = delegate as? EditorView.Coordinator {
            coordinator.text.wrappedValue = formatted
            coordinator.lineCount.wrappedValue = lineStartOffsets.count
        }
    }

    private func countNewlines(in value: String) -> Int {
        value.filter { $0 == "\n" }.count
    }

    override func keyDown(with event: NSEvent) {
        if handleKeyDown(event) {
            return
        }
        super.keyDown(with: event)
    }
}

struct EditorView: NSViewRepresentable {
    @Binding var text: String
    @Binding var lineCount: Int
    var errorLine: Int?
    var editorFont: NSFont
    var showLineNumbers: Bool
    var autoFormatOnSave: Bool

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
        textView.font = editorFont
        textView.textColor = NSColor.textColor
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.autoFormatOnSave = autoFormatOnSave
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.allowsUndo = true
        textView.usesFindBar = true

        textView.string = text
        textView.applyInitialHighlighting()

        textView.onFormatRequest = { [weak textView] in textView?.performFormat() }

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.verticalRulerView = LineNumberRulerView(textView: textView)
        scrollView.hasVerticalRuler = showLineNumbers
        scrollView.rulersVisible = showLineNumbers

        if let rulerView = scrollView.verticalRulerView as? LineNumberRulerView {
            rulerView.refresh(using: editorFont)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? CodeTextView else { return }
        
        textView.onFormatRequest = { [weak textView] in textView?.performFormat() }

        textView.autoFormatOnSave = autoFormatOnSave

        let fontChanged = textView.font != editorFont
        if fontChanged {
            textView.font = editorFont
        }

        if textView.needsUpdate(for: text) {
            let previousRanges = textView.selectedRanges
            let newText = text as NSString
            textView.string = text
            textView.selectedRanges = previousRanges.map {
                ($0.rangeValue.clamped(to: newText.length) ?? NSRange(location: 0, length: 0)) as NSValue
            }
            textView.applyInitialHighlighting()

            if let rulerView = scrollView.verticalRulerView as? LineNumberRulerView {
                rulerView.resetLineCount(using: text)
            }
        }

        if scrollView.hasVerticalRuler != showLineNumbers {
            scrollView.hasVerticalRuler = showLineNumbers
        }
        if scrollView.rulersVisible != showLineNumbers {
            scrollView.rulersVisible = showLineNumbers
        }

        if fontChanged, let rulerView = scrollView.verticalRulerView as? LineNumberRulerView {
            rulerView.refresh(using: editorFont)
        }

        textView.setErrorLine(errorLine)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, lineCount: $lineCount)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var lineCount: Binding<Int>

        init(text: Binding<String>, lineCount: Binding<Int>) {
            self.text = text
            self.lineCount = lineCount
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? CodeTextView else { return }
            text.wrappedValue = textView.string
            lineCount.wrappedValue = textView.lineStartOffsets.count
        }
    }
}
