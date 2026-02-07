import Testing
import UniformTypeIdentifiers
@testable import MacUML

@Suite("Mermaid Document Tests")
struct MermaidDocumentTests {

    @Test("Default document template is populated")
    func defaultTemplateIsPopulated() {
        let document = MermaidDocument()
        #expect(!document.text.isEmpty)
        #expect(document.text.contains("sequenceDiagram"))
    }

    @Test("Readable content types include Mermaid and plain text")
    func readableContentTypes() {
        #expect(MermaidDocument.readableContentTypes.contains(.mermaidMMD))
        #expect(MermaidDocument.readableContentTypes.contains(.mermaid))
        #expect(MermaidDocument.readableContentTypes.contains(.plainText))
    }

    @Test("Writable content types include Mermaid only")
    func writableContentTypes() {
        #expect(MermaidDocument.writableContentTypes.contains(.mermaidMMD))
        #expect(MermaidDocument.writableContentTypes.contains(.mermaid))
        #expect(!MermaidDocument.writableContentTypes.contains(.plainText))
    }

    @Test("Round-trip preserves custom text")
    func roundTripPreservesText() throws {
        let mermaid = "flowchart TD\n  TroyBarnes-->AbedNadir\n  AbedNadir-->GreendaleCommunityCollege"
        let restored = try MermaidDocument(fileWrapper: MermaidDocument(text: mermaid).toFileWrapper())
        #expect(restored.text == mermaid)
    }

    @Test("Round-trip preserves empty string")
    func roundTripEmptyString() throws {
        let restored = try MermaidDocument(fileWrapper: MermaidDocument(text: "").toFileWrapper())
        #expect(restored.text == "")
    }

    @Test("Non-UTF8 data throws fileReadCorruptFile")
    func nonUTF8DataThrows() throws {
        let invalidUTF8 = Data([0xC0, 0xAF, 0xFE, 0xFF])
        let wrapper = FileWrapper(regularFileWithContents: invalidUTF8)
        #expect(throws: CocoaError(.fileReadCorruptFile)) {
            try MermaidDocument(fileWrapper: wrapper)
        }
    }
}
