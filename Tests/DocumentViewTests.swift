import Testing
@testable import MacUML

@Suite("Document View Tests")
struct DocumentViewTests {
    @Test("Line count matches editor line offsets")
    func lineCountMatchesEditorOffsets() {
        #expect(DocumentView.lineCount(in: "") == 1)
        #expect(DocumentView.lineCount(in: "A") == 1)
        #expect(DocumentView.lineCount(in: "A\nB") == 2)
        #expect(DocumentView.lineCount(in: "A\nB\n") == 2)
        #expect(DocumentView.lineCount(in: "A\r\nB\r\nC") == 3)
    }
}
