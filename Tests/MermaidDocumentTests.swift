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
}
