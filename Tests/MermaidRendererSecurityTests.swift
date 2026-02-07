import Testing
import WebKit
@testable import MacUML

@Suite("Mermaid Renderer Security Tests")
struct MermaidRendererSecurityTests {
    private let trustedPreviewURL = MermaidRenderer.normalizedFileURL(
        URL(fileURLWithPath: "/tmp/preview.html")
    )

    private var trustedLocalFiles: Set<URL> {
        [trustedPreviewURL]
    }

    @Test("Allows trusted local preview file URL")
    func allowsTrustedFileURL() {
        let policy = MermaidRenderer.navigationPolicy(
            for: trustedPreviewURL,
            trustedLocalFiles: trustedLocalFiles
        )
        #expect(policy == .allow)
    }

    @Test("Allows normalized trusted local preview file URL")
    func allowsNormalizedTrustedFileURL() {
        let policy = MermaidRenderer.navigationPolicy(
            for: URL(fileURLWithPath: "/tmp/./preview.html"),
            trustedLocalFiles: trustedLocalFiles
        )
        #expect(policy == .allow)
    }

    @Test("Blocks untrusted local file URL")
    func blocksUntrustedFileURL() {
        let policy = MermaidRenderer.navigationPolicy(
            for: URL(fileURLWithPath: "/tmp/not-trusted.mmd"),
            trustedLocalFiles: trustedLocalFiles
        )
        #expect(policy == .cancel)
    }

    @Test("Allows about:blank")
    func allowsAboutBlank() {
        let policy = MermaidRenderer.navigationPolicy(
            for: URL(string: "about:blank"),
            trustedLocalFiles: trustedLocalFiles
        )
        #expect(policy == .allow)
    }

    @Test("Blocks non-blank about URLs")
    func blocksNonBlankAboutURL() {
        let policy = MermaidRenderer.navigationPolicy(
            for: URL(string: "about:config"),
            trustedLocalFiles: trustedLocalFiles
        )
        #expect(policy == .cancel)
    }

    @Test("Blocks remote HTTPS URLs")
    func blocksRemoteURL() {
        let policy = MermaidRenderer.navigationPolicy(
            for: URL(string: "https://example.com"),
            trustedLocalFiles: trustedLocalFiles
        )
        #expect(policy == .cancel)
    }

    @Test("Blocks remote HTTP URLs")
    func blocksRemoteHTTPURL() {
        let policy = MermaidRenderer.navigationPolicy(
            for: URL(string: "http://example.com"),
            trustedLocalFiles: trustedLocalFiles
        )
        #expect(policy == .cancel)
    }

    @Test("Blocks javascript URLs")
    func blocksJavaScriptURL() {
        let policy = MermaidRenderer.navigationPolicy(
            for: URL(string: "javascript:alert('nope')"),
            trustedLocalFiles: trustedLocalFiles
        )
        #expect(policy == .cancel)
    }

    @Test("Blocks data URLs")
    func blocksDataURL() {
        let policy = MermaidRenderer.navigationPolicy(
            for: URL(string: "data:text/plain,hello"),
            trustedLocalFiles: trustedLocalFiles
        )
        #expect(policy == .cancel)
    }

    @Test("Blocks nil URLs")
    func blocksNilURL() {
        let policy = MermaidRenderer.navigationPolicy(
            for: nil,
            trustedLocalFiles: trustedLocalFiles
        )
        #expect(policy == .cancel)
    }
}
