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

    private static let defaultContent: String = {
        let fallback = "sequenceDiagram\n    Troy->>Abed: Hello\n"
        guard let url = Bundle.appResource(name: "DefaultDiagram", extension: "mmd") else {
            Logging.logger(category: "document").error("Default diagram resource is missing")
            return fallback
        }
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            Logging.logger(category: "document").error("Cannot read default diagram: \(error.localizedDescription)")
            return fallback
        }
    }()
}
