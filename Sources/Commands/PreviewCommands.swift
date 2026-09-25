import SwiftUI

enum DocumentLayout: String, CaseIterable {
    case editor, split, preview

    var title: String {
        switch self {
        case .editor: "Editor Only"
        case .split: "Editor and Preview"
        case .preview: "Preview Only"
        }
    }

    var symbol: String {
        switch self {
        case .editor: "text.alignleft"
        case .split: "rectangle.split.2x1"
        case .preview: "photo"
        }
    }
}

private struct FocusedLayoutKey: FocusedValueKey {
    typealias Value = Binding<DocumentLayout>
}

extension FocusedValues {
    var documentLayout: Binding<DocumentLayout>? {
        get { self[FocusedLayoutKey.self] }
        set { self[FocusedLayoutKey.self] = newValue }
    }
}

struct PreviewCommands: Commands {
    @FocusedValue(\.documentLayout) private var layout
    @FocusedValue(\.renderer) private var renderer

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button("Editor Only") { layout?.wrappedValue = .editor }
                .keyboardShortcut("1")
                .disabled(layout == nil)
            Button("Editor and Preview") { layout?.wrappedValue = .split }
                .keyboardShortcut("2")
                .disabled(layout == nil)
            Button("Preview Only") { layout?.wrappedValue = .preview }
                .keyboardShortcut("3")
                .disabled(layout == nil)
            Divider()
            Toggle(
                "Live Preview",
                isOn: Binding(
                    get: { renderer?.isLivePreviewEnabled ?? false },
                    set: { renderer?.isLivePreviewEnabled = $0 }
                )
            )
            .disabled(renderer == nil)
            Button("Refresh Preview") { renderer?.refreshCurrentSource() }
                .keyboardShortcut("r")
                .disabled(renderer == nil)
            Divider()
            Button("Zoom In") { renderer?.zoomIn() }
                .keyboardShortcut("+")
                .disabled(renderer == nil)
            Button("Zoom Out") { renderer?.zoomOut() }
                .keyboardShortcut("-")
                .disabled(renderer == nil)
            Button("Fit to Window") { renderer?.resetZoom() }
                .keyboardShortcut("0")
                .disabled(renderer == nil)
        }
    }
}
