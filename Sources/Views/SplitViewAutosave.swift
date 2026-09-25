import AppKit
import SwiftUI

struct SplitViewAutosave: NSViewRepresentable {
    func makeNSView(context: Context) -> SplitAutosaveView { SplitAutosaveView() }
    func updateNSView(_ view: SplitAutosaveView, context: Context) {}
}

final class SplitAutosaveView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            var ancestor = self?.superview
            while let view = ancestor {
                if let split = view as? NSSplitView, split.isVertical {
                    split.autosaveName = "MacUML.DocumentSplit"
                    return
                }
                ancestor = view.superview
            }
        }
    }
}
