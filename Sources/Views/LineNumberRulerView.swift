import AppKit

private enum Constants {
    static let defaultFontSize: CGFloat = 11
    static let minimumThickness: CGFloat = 36
    static let horizontalPadding: CGFloat = 8
    static let fontSizeRatio: CGFloat = 0.85
    static let minimumFontSize: CGFloat = 10
    static let separatorLineXOffset: CGFloat = 0.5
    static let separatorAlpha: CGFloat = 0.6
}

final class LineNumberRulerView: NSRulerView {
    private weak var textView: CodeTextView?
    private var lineNumberAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedDigitSystemFont(ofSize: Constants.defaultFontSize, weight: .regular),
        .foregroundColor: NSColor.secondaryLabelColor
    ]
    private var cachedLineCount = 1
    init(textView: CodeTextView) {
        guard let scrollView = textView.enclosingScrollView else {
            fatalError("LineNumberRulerView requires a text view in a scroll view")
        }

        self.textView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        cachedLineCount = max(1, textView.lineStartOffsets.count)
        configureObservers()
        recalculateThickness()
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func refresh(using editorFont: NSFont) {
        let newFont = NSFont.monospacedDigitSystemFont(ofSize: max(Constants.minimumFontSize, editorFont.pointSize * Constants.fontSizeRatio), weight: .regular)
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
        cachedLineCount = max(1, textView?.lineStartOffsets.count ?? 1)
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

        let separatorX = bounds.maxX - Constants.separatorLineXOffset
        NSColor.separatorColor.withAlphaComponent(Constants.separatorAlpha).setStroke()
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
                selector: #selector(handleBoundsChange),
                name: NSView.boundsDidChangeNotification,
                object: contentView
            )
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTextDidChange),
            name: NSText.didChangeNotification,
            object: textView
        )
    }

    @objc private func handleBoundsChange() {
        needsDisplay = true
    }

    @objc private func handleTextDidChange() {
        guard let textView else { return }
        cachedLineCount = max(1, textView.lineStartOffsets.count)
        recalculateThickness()
        needsDisplay = true
    }

    private func recalculateThickness() {
        let digits = String(max(1, cachedLineCount)).count
        let sample = String(repeating: "8", count: digits) as NSString
        let labelWidth = sample.size(withAttributes: lineNumberAttributes).width
        let targetThickness = max(Constants.minimumThickness, ceil(labelWidth + (Constants.horizontalPadding * 2)))

        if abs(ruleThickness - targetThickness) > .ulpOfOne {
            ruleThickness = targetThickness
        }
    }

    private func lineNumber(for glyphLocation: Int, layoutManager: NSLayoutManager) -> Int {
        guard layoutManager.numberOfGlyphs > 0 else { return 1 }
        guard let offsets = textView?.lineStartOffsets, !offsets.isEmpty else { return 1 }

        let glyphIndex = min(max(glyphLocation, 0), layoutManager.numberOfGlyphs - 1)
        let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)

        guard charIndex > 0 else { return 1 }

        return max(1, CodeTextView.firstIndex(greaterThan: charIndex, in: offsets))
    }

    private func draw(lineNumber: Int, atY y: CGFloat) {
        let label = "\(lineNumber)" as NSString
        let size = label.size(withAttributes: lineNumberAttributes)
        let x = ruleThickness - Constants.horizontalPadding - size.width
        label.draw(at: NSPoint(x: x, y: y + 1), withAttributes: lineNumberAttributes)
    }
}
