import AppKit

/// A list of completion suggestions that floats below the editor's caret without taking keyboard focus.
final class CompletionPanel: NSPanel, NSTableViewDataSource, NSTableViewDelegate {
    private enum Constants {
        static let maximumVisibleRows = 8
        static let minimumWidth: CGFloat = 120
        static let maximumWidth: CGFloat = 360
        /// Space between the panel's edge and the suggestion text.
        static let textInset: CGFloat = 10
        static let verticalPadding: CGFloat = 4
        static let rowPadding: CGFloat = 4
        static let cornerRadius: CGFloat = 6
        static let caretGap: CGFloat = 2
    }

    private static let cellIdentifier = NSUserInterfaceItemIdentifier("suggestion")

    private let tableView = CompletionTableView()
    private var suggestions: [String] = []
    private var font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

    /// Called with the suggestion the user clicks.
    var onAccept: ((String) -> Void)?

    var selectedSuggestion: String? {
        suggestions.indices.contains(tableView.selectedRow) ? suggestions[tableView.selectedRow] : nil
    }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Constants.minimumWidth, height: Constants.minimumWidth),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true

        let column = NSTableColumn(identifier: Self.cellIdentifier)
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.style = .plain
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.backgroundColor = .clear
        tableView.intercellSpacing = .zero
        tableView.focusRingType = .none
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(acceptClickedRow)
        tableView.setAccessibilityLabel("Completions")

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let background = NSVisualEffectView()
        background.material = .menu
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = Constants.cornerRadius
        background.layer?.masksToBounds = true
        contentView = background
        scrollView.frame = background.bounds.insetBy(dx: 0, dy: Constants.verticalPadding)
        scrollView.autoresizingMask = [.width, .height]
        background.addSubview(scrollView)
    }

    /// Replaces the list and selects its first suggestion.
    func show(_ suggestions: [String], font: NSFont) {
        self.suggestions = suggestions
        self.font = font
        tableView.rowHeight = ceil(NSLayoutManager().defaultLineHeight(for: font)) + Constants.rowPadding
        tableView.reloadData()
        select(row: 0)
    }

    func moveSelection(by offset: Int) {
        select(row: min(max(tableView.selectedRow + offset, 0), suggestions.count - 1))
    }

    /// Floats the list below `wordRect`, a rectangle in screen coordinates, or above it when the screen has no room
    /// below.
    func present(below wordRect: NSRect, in window: NSWindow) {
        let textWidth = suggestions.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        let width = min(max(ceil(textWidth) + 3 * Constants.textInset, Constants.minimumWidth), Constants.maximumWidth)
        let rows = CGFloat(min(suggestions.count, Constants.maximumVisibleRows))
        let height = rows * tableView.rowHeight + 2 * Constants.verticalPadding
        var frame = NSRect(
            x: wordRect.minX - Constants.textInset, y: wordRect.minY - Constants.caretGap - height,
            width: width, height: height)
        if let visibleFrame = window.screen?.visibleFrame {
            if frame.minY < visibleFrame.minY {
                frame.origin.y = wordRect.maxY + Constants.caretGap
            }
            frame.origin.x = max(visibleFrame.minX, min(frame.minX, visibleFrame.maxX - frame.width))
        }
        setFrame(frame, display: true)
        tableView.sizeLastColumnToFit()
        if parent == nil {
            window.addChildWindow(self, ordered: .above)
        }
    }

    func dismiss() {
        parent?.removeChildWindow(self)
        orderOut(nil)
    }

    private func select(row: Int) {
        guard suggestions.indices.contains(row) else { return }
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
    }

    @objc private func acceptClickedRow() {
        guard suggestions.indices.contains(tableView.clickedRow) else { return }
        onAccept?(suggestions[tableView.clickedRow])
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        suggestions.count
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        CompletionRowView()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = tableView.makeView(withIdentifier: Self.cellIdentifier, owner: nil) as? NSTableCellView ?? makeCell()
        cell.textField?.stringValue = suggestions[row]
        cell.textField?.font = font
        return cell
    }

    private func makeCell() -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = Self.cellIdentifier
        let label = NSTextField(labelWithString: "")
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(label)
        cell.textField = label
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: Constants.textInset),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -Constants.textInset),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }
}

/// Takes the first click even though its window never becomes key.
private final class CompletionTableView: NSTableView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

/// Draws the selection in the accent color, as a menu does, even though its window never becomes key.
private final class CompletionRowView: NSTableRowView {
    override var isEmphasized: Bool {
        get { true }
        set {}
    }

    override func drawSelection(in dirtyRect: NSRect) {
        NSColor.selectedContentBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 0), xRadius: 4, yRadius: 4).fill()
    }
}
