import Testing
import WebKit
@testable import MacUML

@Suite("Mermaid Renderer Security Tests")
struct MermaidRendererSecurityTests {

    @Test("Allows local file URLs")
    func allowsFileURL() {
        let policy = MermaidRenderer.navigationPolicy(for: URL(fileURLWithPath: "/tmp/test.mmd"))
        #expect(policy == .allow)
    }

    @Test("Allows about scheme")
    func allowsAboutScheme() {
        let policy = MermaidRenderer.navigationPolicy(for: URL(string: "about:blank"))
        #expect(policy == .allow)
    }

    @Test("Blocks remote HTTPS URLs")
    func blocksRemoteURL() {
        let policy = MermaidRenderer.navigationPolicy(for: URL(string: "https://example.com"))
        #expect(policy == .cancel)
    }

    @Test("Blocks remote HTTP URLs")
    func blocksRemoteHTTPURL() {
        let policy = MermaidRenderer.navigationPolicy(for: URL(string: "http://example.com"))
        #expect(policy == .cancel)
    }

    @Test("Blocks javascript URLs")
    func blocksJavaScriptURL() {
        let policy = MermaidRenderer.navigationPolicy(for: URL(string: "javascript:alert('nope')"))
        #expect(policy == .cancel)
    }

    @Test("Blocks data URLs")
    func blocksDataURL() {
        let policy = MermaidRenderer.navigationPolicy(for: URL(string: "data:text/plain,hello"))
        #expect(policy == .cancel)
    }

    @Test("Blocks nil URLs")
    func blocksNilURL() {
        let policy = MermaidRenderer.navigationPolicy(for: nil)
        #expect(policy == .cancel)
    }
}
