import AppKit
import Testing

@testable import MacUML

@Suite("Document Save Commands")
@MainActor
struct DocumentCommandsTests {
    @Test("Save operations serialize prepared source", arguments: [DocumentSaveOperation.save, .saveAs])
    func prepareBeforeSave(_ operation: DocumentSaveOperation) throws {
        let document = SaveProbeDocument()
        document.source = "flowchart TD   \n\tTroy --> Abed   "
        operation.perform(on: document) {
            document.source = MermaidFormatter.format(document.source)
        }
        let data = try #require(document.savedData)
        #expect(String(decoding: data, as: UTF8.self) == document.source)
        #expect(document.source == "flowchart TD\n\tTroy --> Abed\n")
    }

    @Test("Autosave serialization preserves the source as typed")
    func autosavePreservesSource() throws {
        let source = "flowchart TD   \n  Troy --> Abed  "
        let wrapper = MermaidDocument(text: source).fileWrapper()
        #expect(try MermaidDocument(fileWrapper: wrapper).text == source)
    }
}

@MainActor
private final class SaveProbeDocument: NSDocument {
    var source = ""
    var savedData: Data?

    override func save(_ sender: Any?) {
        savedData = MermaidDocument(text: source).fileWrapper().regularFileContents
    }

    override func saveAs(_ sender: Any?) { save(sender) }
}
