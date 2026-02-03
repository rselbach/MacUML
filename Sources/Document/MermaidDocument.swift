import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static var mermaid: UTType {
        UTType(importedAs: "com.mermaid.mmd", conformingTo: .plainText)
    }
}

struct MermaidDocument: FileDocument {
    var text: String

    static var readableContentTypes: [UTType] { [.mermaid, .plainText] }

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
        let data = text.data(using: .utf8)!
        return .init(regularFileWithContents: data)
    }

    private static let defaultContent = """
flowchart TD
    A[Start] --> B{Decision}
    B -->|Yes| C[Do something]
    B -->|No| D[Do something else]
    C --> E[End]
    D --> E
"""
}
