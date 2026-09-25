import SwiftUI

enum DiagramExportAction: CaseIterable {
    case savePNG, saveSVG, copyPNG, copySVG

    var title: String {
        switch self {
        case .savePNG: "Export PNG…"
        case .saveSVG: "Export SVG…"
        case .copyPNG: "Copy as PNG"
        case .copySVG: "Copy as SVG"
        }
    }

    var format: DiagramExportFormat {
        switch self {
        case .savePNG, .copyPNG: .png
        case .saveSVG, .copySVG: .svg
        }
    }

    var writesFile: Bool { self == .savePNG || self == .saveSVG }
}

struct DocumentExportActions {
    var isEnabled: Bool
    var perform: (DiagramExportAction) -> Void
}

private struct FocusedExportKey: FocusedValueKey {
    typealias Value = DocumentExportActions
}

extension FocusedValues {
    var exportDiagram: DocumentExportActions? {
        get { self[FocusedExportKey.self] }
        set { self[FocusedExportKey.self] = newValue }
    }
}

struct ExportCommands: Commands {
    @FocusedValue(\.exportDiagram) private var actions

    var body: some Commands {
        CommandGroup(after: .importExport) {
            ExportButtons(actions: actions)
        }
    }
}

struct ExportButtons: View {
    let actions: DocumentExportActions?

    var body: some View {
        Button("Export PNG…") { actions?.perform(.savePNG) }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(actions?.isEnabled != true)
        Button("Export SVG…") { actions?.perform(.saveSVG) }
            .disabled(actions?.isEnabled != true)
        Divider()
        Button("Copy as PNG") { actions?.perform(.copyPNG) }
            .disabled(actions?.isEnabled != true)
        Button("Copy as SVG") { actions?.perform(.copySVG) }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(actions?.isEnabled != true)
    }
}
