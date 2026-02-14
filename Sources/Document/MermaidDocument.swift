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

    private static let defaultContent = """
sequenceDiagram
    participant Jeff
    participant Abed
    participant StarBurns
    participant Dean
    participant StudyGroup as Study Group

    Jeff->>Abed: We need chicken fingers
    Abed->>Abed: Becomes fry cook
    Note over Abed: Controls the supply
    
    Abed->>StarBurns: You handle distribution
    StarBurns->>StudyGroup: Chicken fingers... for a price
    StudyGroup->>StarBurns: Bribes & favors
    StarBurns->>Abed: Reports tribute
    
    Jeff->>Abed: I need extra fingers for a date
    Abed-->>Jeff: You'll wait like everyone else
    Jeff->>Jeff: What have we created?
    
    Dean->>Abed: Why is everyone so happy?
    Abed-->>Dean: Efficient cafeteria management
    Dean->>Dean: Something's not right...
    
    StudyGroup->>Jeff: This has gone too far
    Jeff->>Abed: We have to shut it down
    Abed->>Abed: Destroys the fryer
    Note over Abed: The empire crumbles
"""
}
