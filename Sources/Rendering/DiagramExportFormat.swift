import AppKit
import UniformTypeIdentifiers

/// The backdrop drawn behind exported diagrams.
enum ExportBackground: String, CaseIterable {
    /// The preview background of the current theme.
    case theme
    /// No backdrop.
    case transparent

    var label: String {
        switch self {
        case .theme: "Theme Color"
        case .transparent: "Transparent"
        }
    }
}

enum DiagramExportFormat: String {
    case png
    case svg

    var contentType: UTType { self == .png ? .png : .svg }
    var pasteboardType: NSPasteboard.PasteboardType {
        self == .png ? .png : NSPasteboard.PasteboardType(UTType.svg.identifier)
    }
}
