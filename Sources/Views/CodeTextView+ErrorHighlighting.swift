import AppKit

extension CodeTextView {
    private enum ErrorHighlightingConstants {
        static let errorBackgroundColor = NSColor.systemRed.withAlphaComponent(0.2)
        static let errorUnderlineColor = NSColor.systemRed
    }

    func setErrorLine(_ line: Int?) {
        guard errorLine != line else { return }
        errorLine = line
        applyErrorHighlighting()
    }

    func applyErrorHighlighting() {
        guard let storage = textStorage else { return }
        let text = storage.string as NSString

        if let previousErrorRange {
            removeErrorAttributes(in: previousErrorRange, storage: storage)
            self.previousErrorRange = nil
        }

        guard let errorLine, let range = lineRange(for: errorLine, in: text) else { return }

        storage.addAttribute(.backgroundColor, value: ErrorHighlightingConstants.errorBackgroundColor, range: range)
        storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        storage.addAttribute(.underlineColor, value: ErrorHighlightingConstants.errorUnderlineColor, range: range)
        previousErrorRange = range
    }

    /// O(log n) line range lookup using cached line start offsets
    func lineStartOffset(for oneBasedLine: Int) -> Int? {
        guard oneBasedLine > 0, oneBasedLine <= lineStartOffsets.count else { return nil }
        return lineStartOffsets[oneBasedLine - 1]
    }

    private func removeErrorAttributes(in range: NSRange, storage: NSTextStorage) {
        guard let clampedRange = range.clamped(to: storage.length) else { return }
        storage.removeAttribute(.underlineStyle, range: clampedRange)
        storage.removeAttribute(.underlineColor, range: clampedRange)
        storage.removeAttribute(.backgroundColor, range: clampedRange)
    }

    private func lineRange(for oneBasedLine: Int, in text: NSString) -> NSRange? {
        guard let lineStart = lineStartOffset(for: oneBasedLine) else { return nil }
        return text.lineRange(for: NSRange(location: lineStart, length: 0))
    }
}
