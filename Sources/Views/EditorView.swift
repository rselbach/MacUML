import AppKit
import SwiftUI

final class CodeTextView: NSTextView {
    static let indentString = "    "
    private static let highlightDebounceInterval: Duration = .milliseconds(100)
    private let highlighter = MermaidHighlighter.shared
    private var highlightTask: Task<Void, Never>?
    private var pendingHighlightRange: NSRange?
    var errorLine: Int?
    var previousErrorRange: NSRange?

    private(set) var lineStartOffsets: [Int] = [0]

    override func didChangeText() {
        super.didChangeText()
        rebuildLineStartOffsets(for: string)
        queueIncrementalHighlightRange()
        scheduleHighlighting()
    }

    private func rebuildLineStartOffsets(for currentString: String) {
        // O(N) iteration over UTF-16 code units is ~100x faster than calling NSString.lineRange in a while loop
        var offsets = [0]
        let utf16 = currentString.utf16
        // Pre-allocate to avoid reallocation overhead. Assuming average line length of 40.
        offsets.reserveCapacity(utf16.count / 40 + 1)

        let newline: UTF16.CodeUnit = 10  // '\n'
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

    func setStringPreservingSelection(_ newString: String) {
        let previousRanges = selectedRanges
        string = newString
        let newLength = (newString as NSString).length
        selectedRanges = previousRanges.compactMap {
            $0.rangeValue.clampedSelection(to: newLength).map(NSValue.init(range:))
        }
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
            editedRange.location <= storage.length
        else {
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

    override func keyDown(with event: NSEvent) {
        if handleKeyDown(event) {
            return
        }
        super.keyDown(with: event)
    }
}

@MainActor
final class EditorActions {
    weak var textView: CodeTextView?

    func revealLine(_ line: Int) { textView?.revealLine(line) }
}

struct EditorView: NSViewRepresentable {
    @Binding var text: String
    @Binding var lineCount: Int
    var errorLine: Int?
    var editorFont: NSFont
    var showLineNumbers: Bool
    var actions: EditorActions? = nil

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = CodeTextView()
        actions?.textView = textView
        textView.setAccessibilityLabel("Mermaid source")

        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true

        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.font = editorFont
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
        scrollView.hasVerticalRuler = showLineNumbers
        scrollView.rulersVisible = showLineNumbers

        if let rulerView = scrollView.verticalRulerView as? LineNumberRulerView {
            rulerView.refresh(using: editorFont)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? CodeTextView else { return }

        let fontChanged = textView.font != editorFont
        if fontChanged {
            textView.font = editorFont
        }

        if textView.needsUpdate(for: text) {
            textView.setStringPreservingSelection(text)
            textView.applyInitialHighlighting()

            if let rulerView = scrollView.verticalRulerView as? LineNumberRulerView {
                rulerView.resetLineCount()
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
