import AppKit

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
