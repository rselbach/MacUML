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

    init(text: String = defaultContent) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let string = String(data: data, encoding: .utf8)
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = string
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let data = text.data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        return .init(regularFileWithContents: data)
    }

    private static let defaultContent: String = {
        guard let url = Bundle.appResource(name: "DefaultDiagram", extension: "mmd"),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return "sequenceDiagram\n    A->>B: Hello"
        }
        return content
    }()
}
