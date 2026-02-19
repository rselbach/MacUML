import SwiftUI
import AppKit

final class CodeTextView: NSTextView {
    static let indentString = "    "
    private static let highlightDebounceInterval: TimeInterval = 0.1
    private let highlighter = MermaidHighlighter.shared
    private var highlightWorkItem: DispatchWorkItem?
    private var pendingHighlightRange: NSRange?
    var errorLine: Int?
    var previousErrorRange: NSRange?

    private(set) var lineStartOffsets: [Int] = [0]
    private var textHash: Int = 0

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
        rebuildLineStartOffsets()
        queueIncrementalHighlightRange()
        scheduleHighlighting()
    }

    private func rebuildLineStartOffsets() {
        let currentString = string
        textHash = currentString.hashValue

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

    func needsUpdate(for newText: String) -> Bool {
        newText.hashValue != textHash
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
        rebuildLineStartOffsets()
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

        if textView.needsUpdate(for: text) {
            let previousRanges = textView.selectedRanges
            let newText = text as NSString
            textView.string = text
            textView.selectedRanges = previousRanges.map { 
                $0.rangeValue.safeClamped(to: newText.length) as NSValue 
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