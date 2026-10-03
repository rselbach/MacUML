import AppKit
import SwiftUI

final class CodeTextView: NSTextView {
    private static let highlightDebounceInterval: Duration = .milliseconds(100)
    private let highlighter = MermaidHighlighter.shared
    private var highlightTask: Task<Void, Never>?
    private var pendingHighlightRange: NSRange?
    var errorLine: Int?
    var previousErrorRange: NSRange?
    var didMoveToWindowHandler: (() -> Void)?

    private(set) var lineStartOffsets: [Int] = [0]

    override func didChangeText() {
        super.didChangeText()
        rebuildLineStartOffsets(for: string)
        queueIncrementalHighlightRange()
        scheduleHighlighting()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        didMoveToWindowHandler?()
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

    /// Replaces the text as one undoable edit so earlier undo steps keep valid ranges.
    func setStringPreservingSelection(_ newString: String) {
        let previousRanges = selectedRanges
        let oldText = string as NSString
        let newText = newString as NSString
        let (oldRange, newRange) = Self.changedRanges(from: oldText, to: newText)
        let replacement = newText.substring(with: newRange)

        breakUndoCoalescing()
        guard shouldChangeText(in: oldRange, replacementString: replacement) else { return }
        textStorage?.replaceCharacters(in: oldRange, with: replacement)
        didChangeText()
        breakUndoCoalescing()

        selectedRanges = previousRanges.compactMap {
            $0.rangeValue.clampedSelection(to: newText.length).map(NSValue.init(range:))
        }
    }

    /// Returns the differing span between two strings, trimmed of their common prefix and suffix.
    static func changedRanges(from oldText: NSString, to newText: NSString) -> (old: NSRange, new: NSRange) {
        let oldLength = oldText.length
        let newLength = newText.length
        let limit = min(oldLength, newLength)

        var prefix = 0
        while prefix < limit, oldText.character(at: prefix) == newText.character(at: prefix) {
            prefix += 1
        }
        // keep surrogate pairs intact
        if prefix > 0, UTF16.isLeadSurrogate(oldText.character(at: prefix - 1)) {
            prefix -= 1
        }

        var suffix = 0
        while suffix < limit - prefix,
            oldText.character(at: oldLength - suffix - 1) == newText.character(at: newLength - suffix - 1)
        {
            suffix += 1
        }
        if suffix > 0, UTF16.isTrailSurrogate(oldText.character(at: oldLength - suffix)) {
            suffix -= 1
        }

        return (
            NSRange(location: prefix, length: oldLength - prefix - suffix),
            NSRange(location: prefix, length: newLength - prefix - suffix)
        )
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
    private(set) var textView: CodeTextView?
    private var scrollView: NSScrollView?
    private var coordinator: EditorView.Coordinator?
    private var pendingLine: Int?
    private var restoresFocus = false

    func rememberFocus() {
        guard let textView, let window = textView.window else { return }
        restoresFocus = window.firstResponder === textView
    }

    func retainedScrollView(with coordinator: EditorView.Coordinator) -> NSScrollView? {
        guard let scrollView, let textView else { return nil }
        retain(scrollView: scrollView, textView: textView, coordinator: coordinator)
        return scrollView
    }

    func retain(scrollView: NSScrollView, textView: CodeTextView, coordinator: EditorView.Coordinator) {
        self.scrollView = scrollView
        self.textView = textView
        self.coordinator = coordinator
        coordinator.attach(to: textView)
        textView.didMoveToWindowHandler = { [weak self, weak textView] in
            guard let textView else { return }
            self?.restoreInteraction(for: textView)
        }
        restoreInteraction(for: textView)
    }

    private func restoreInteraction(for textView: CodeTextView) {
        guard pendingLine != nil || restoresFocus else { return }
        // SwiftUI finishes removing the old representable container after installing its replacement.
        // Wait through both queue turns so that teardown cannot reset the replacement's first responder.
        DispatchQueue.main.async { [weak self, weak textView] in
            DispatchQueue.main.async {
                guard let self, let textView, self.textView === textView, let window = textView.window else { return }
                if let line = self.pendingLine {
                    self.pendingLine = nil
                    self.restoresFocus = false
                    textView.revealLine(line)
                } else if self.restoresFocus, window.makeFirstResponder(textView) {
                    self.restoresFocus = false
                }
            }
        }
    }

    func revealLine(_ line: Int) {
        guard let textView, textView.window != nil else {
            pendingLine = line
            return
        }
        textView.revealLine(line)
    }

    func editorDidUpdate(_ textView: CodeTextView) {
        restoreInteraction(for: textView)
    }
}

final class EditorContainerView: NSView {
    let scrollView: NSScrollView

    init(scrollView: NSScrollView) {
        self.scrollView = scrollView
        super.init(frame: .zero)
        scrollView.frame = bounds
        scrollView.autoresizingMask = [.width, .height]
        addSubview(scrollView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

struct EditorView: NSViewRepresentable {
    @Binding var text: String
    @Binding var lineCount: Int
    var errorLine: Int?
    var editorFont: NSFont
    var showLineNumbers: Bool
    var actions: EditorActions? = nil

    func makeNSView(context: Context) -> EditorContainerView {
        if let scrollView = actions?.retainedScrollView(with: context.coordinator) {
            return EditorContainerView(scrollView: scrollView)
        }

        let scrollView = NSScrollView()
        let textView = CodeTextView()
        textView.setAccessibilityLabel("Mermaid source")

        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true

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
        context.coordinator.attach(to: textView)

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

        actions?.retain(scrollView: scrollView, textView: textView, coordinator: context.coordinator)

        return EditorContainerView(scrollView: scrollView)
    }

    func updateNSView(_ containerView: EditorContainerView, context: Context) {
        let scrollView = containerView.scrollView
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
        actions?.editorDidUpdate(textView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, lineCount: $lineCount)
    }

    @MainActor
    class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var lineCount: Binding<Int>
        weak var textView: CodeTextView?

        init(text: Binding<String>, lineCount: Binding<Int>) {
            self.text = text
            self.lineCount = lineCount
        }

        func attach(to textView: CodeTextView) {
            self.textView = textView
            textView.delegate = self
            NotificationCenter.default.removeObserver(
                self, name: NSTextStorage.didProcessEditingNotification, object: nil)
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleTextStorageDidProcessEditing(_:)),
                name: NSTextStorage.didProcessEditingNotification,
                object: textView.textStorage
            )
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? CodeTextView,
                text.wrappedValue != textView.string
            else { return }
            text.wrappedValue = textView.string
            lineCount.wrappedValue = textView.lineStartOffsets.count
        }

        @objc private func handleTextStorageDidProcessEditing(_ notification: Notification) {
            guard
                let textStorage = notification.object as? NSTextStorage,
                textStorage.editedMask.contains(.editedCharacters),
                let textView,
                textView.window == nil,
                text.wrappedValue != textStorage.string
            else { return }
            textView.applyInitialHighlighting()
            text.wrappedValue = textStorage.string
            lineCount.wrappedValue = textView.lineStartOffsets.count
        }
    }
}
