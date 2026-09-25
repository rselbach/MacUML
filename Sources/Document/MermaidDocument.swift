import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static var mermaidMMD: UTType {
        UTType(importedAs: "com.mermaid.mmd", conformingTo: .plainText)
    }

    static var mermaid: UTType {
        UTType(importedAs: "com.mermaid.mermaid", conformingTo: .plainText)
    }
}

/// A document representing a Mermaid diagram source file.
///
/// Supports reading and writing `.mmd` and `.mermaid` files with UTF-8 encoding.
/// New documents start with a sample sequence diagram demonstrating basic syntax.
struct MermaidDocument: FileDocument {
    var text: String

    static var readableContentTypes: [UTType] { [.mermaidMMD, .mermaid, .plainText] }
    static var writableContentTypes: [UTType] { [.mermaidMMD, .mermaid] }

    init(text: String = DiagramTemplate.sequence.source) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        try self.init(fileWrapper: configuration.file)
    }

    init(fileWrapper: FileWrapper) throws {
        guard let data = fileWrapper.regularFileContents,
            let string = String(data: data, encoding: .utf8)
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = string
    }

    func fileWrapper(configuration: WriteConfiguration) -> FileWrapper {
        fileWrapper()
    }

    func fileWrapper() -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }

}
