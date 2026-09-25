import AppKit
import UniformTypeIdentifiers

enum DiagramExportFormat: String {
    case png
    case svg

    var contentType: UTType { self == .png ? .png : .svg }
    var pasteboardType: NSPasteboard.PasteboardType {
        self == .png ? .png : NSPasteboard.PasteboardType(UTType.svg.identifier)
    }
}
