import Testing

@testable import MacUML

@Suite("SVG Sanitizer Tests")
struct SVGSanitizerTests {
    @Test("Preserves label markup while removing active content and event handlers")
    func preservesSafeForeignObjectLabels() throws {
        let raw = """
            <svg xmlns=\"http://www.w3.org/2000/svg\" onload=\"alert(1)\">
              <script>alert('x')</script>
              <foreignObject><div xmlns=\"http://www.w3.org/1999/xhtml\"><span><p>Hello</p></span><img src=\"https://evil.test/x\"/></div></foreignObject>
              <g onclick=\"evil()\"><text>Hello</text></g>
            </svg>
            """

        let sanitized = try SVGSanitizer.sanitize(raw)

        #expect(!sanitized.localizedCaseInsensitiveContains("<script"))
        #expect(sanitized.localizedCaseInsensitiveContains("<foreignObject"))
        #expect(!sanitized.localizedCaseInsensitiveContains("<img"))
        #expect(!sanitized.localizedCaseInsensitiveContains("onload="))
        #expect(!sanitized.localizedCaseInsensitiveContains("onclick="))
        #expect(sanitized.contains("<p>Hello</p>"))
        #expect(sanitized.contains("<text>Hello</text>"))
    }

    @Test("Preserves ordinary paint values and local paint servers")
    func preservesSafePaintValues() throws {
        let raw = """
            <svg xmlns=\"http://www.w3.org/2000/svg\">
              <defs><linearGradient id=\"g\"><stop stop-color=\"#fff\"/></linearGradient></defs>
              <rect fill=\"none\" stroke=\"#123456\"/>
              <circle fill=\"rgb(10, 20, 30)\" stroke=\"url(#g)\"/>
            </svg>
            """

        let sanitized = try SVGSanitizer.sanitize(raw)

        #expect(sanitized.contains("fill=\"none\""))
        #expect(sanitized.contains("stroke=\"#123456\""))
        #expect(sanitized.contains("fill=\"rgb(10, 20, 30)\""))
        #expect(sanitized.contains("stroke=\"url(#g)\""))
    }

    @Test("Removes unsafe URL references from attributes")
    func stripsUnsafeURLReferences() throws {
        let raw = """
            <svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\" xmlns:remote=\"http://www.w3.org/1999/xlink\" xml:base=\"https://evil.test/base/\">
              <a href=\"javascript:alert(1)\"><text>link</text></a>
              <rect fill=\"url(http://evil.test/x)\"/>
              <circle stroke=\"url ( https://evil.test/y )\"/>
              <use xlink:href=\"https://evil.test/symbol\"/>
              <use remote:href=\"https://evil.test/aliased-symbol\"/>
            </svg>
            """

        let sanitized = try SVGSanitizer.sanitize(raw)

        #expect(!sanitized.localizedCaseInsensitiveContains("javascript:"))
        #expect(!sanitized.contains("url(http://evil.test/x)"))
        #expect(!sanitized.contains("https://evil.test/y"))
        #expect(!sanitized.contains("https://evil.test/symbol"))
        #expect(!sanitized.contains("https://evil.test/aliased-symbol"))
        #expect(!sanitized.contains("xml:base"))
    }

    @Test("Preserves safe fragment references")
    func keepsSafeFragmentReferences() throws {
        let raw = """
            <svg xmlns=\"http://www.w3.org/2000/svg\">
              <defs><clipPath id=\"c\"><rect width=\"10\" height=\"10\"/></clipPath></defs>
              <rect clip-path=\"url(#c)\"/>
              <use href=\"#c\"/>
            </svg>
            """

        let sanitized = try SVGSanitizer.sanitize(raw)

        #expect(sanitized.contains("clip-path=\"url(#c)\""))
        #expect(sanitized.contains("href=\"#c\""))
    }

    @Test("Sanitizes inline and style-block CSS")
    func sanitizesCSS() throws {
        let raw = """
            <svg xmlns=\"http://www.w3.org/2000/svg\" style=\"fill:url(javascript:alert(1)); @import url(https://evil.test/x.css);\">
              <style>@import url(https://evil.test/x.css); .a{fill:url(javascript:alert(1));}</style>
              <rect class=\"a\"/>
            </svg>
            """

        let sanitized = try SVGSanitizer.sanitize(raw)

        #expect(!sanitized.localizedCaseInsensitiveContains("@import"))
        #expect(!sanitized.localizedCaseInsensitiveContains("javascript:"))
    }

    @Test("Rejects escaped and alternate CSS resource functions")
    func rejectsObfuscatedCSSResources() throws {
        let raw = #"""
            <svg xmlns="http://www.w3.org/2000/svg">
              <foreignObject><div xmlns="http://www.w3.org/1999/xhtml" style="color:#123456;background-image:u\72l(http://127.0.0.1:8765/paint.svg)">Troy</div></foreignObject>
              <rect fill="u\72l(https://evil.test/paint)"/>
              <style>
                @import "https://evil.test/import.css";
                @font-face { font-family: Greendale; src: url(https://evil.test/font.woff2); }
                .option { color: #654321; background-image: image-set("https://evil.test/a.png" 1x); }
                .webkit { fill: #abcdef; background-image: -webkit-image-set("https://evil.test/b.png" 1x); }
              </style>
            </svg>
            """#

        let sanitized = try SVGSanitizer.sanitize(raw)

        #expect(!sanitized.contains("127.0.0.1"))
        #expect(!sanitized.contains("evil.test"))
        #expect(!sanitized.localizedCaseInsensitiveContains("background-image"))
        #expect(!sanitized.localizedCaseInsensitiveContains("@import"))
        #expect(!sanitized.localizedCaseInsensitiveContains("@font-face"))
        #expect(sanitized.contains("color:#123456"))
        #expect(sanitized.contains("color:#654321"))
        #expect(sanitized.contains("fill:#abcdef"))
    }

    @Test("Discards stylesheet processing instructions")
    func discardsStylesheetProcessingInstructions() throws {
        let raw = #"""
            <?xml-stylesheet type="text/css" href="http://127.0.0.1:8765/remote.css"?>
            <svg xmlns="http://www.w3.org/2000/svg"><text>Abed</text></svg>
            """#

        let sanitized = try SVGSanitizer.sanitize(raw)

        #expect(!sanitized.localizedCaseInsensitiveContains("xml-stylesheet"))
        #expect(!sanitized.contains("127.0.0.1"))
        #expect(sanitized.contains("<text>Abed</text>"))
    }

    @Test("Removes SVG animation that can change resource attributes")
    func removesResourceAnimations() throws {
        let raw = """
            <svg xmlns="http://www.w3.org/2000/svg">
              <rect fill="#123456">
                <animate attributeName="fill" values="#123456;url(https://evil.test/paint)"/>
                <set attributeName="fill" to="url(https://evil.test/set)"/>
              </rect>
              <use href="#local">
                <animate attributeName="href" to="https://evil.test/image.svg"/>
              </use>
            </svg>
            """

        let sanitized = try SVGSanitizer.sanitize(raw)

        #expect(!sanitized.localizedCaseInsensitiveContains("<animate"))
        #expect(!sanitized.localizedCaseInsensitiveContains("<set"))
        #expect(!sanitized.contains("evil.test"))
        #expect(sanitized.contains("fill=\"#123456\""))
        #expect(sanitized.contains("href=\"#local\""))
    }

    @Test("Preserves Mermaid label and paint declarations")
    func preservesSafeMermaidCSS() throws {
        let raw = """
            <svg xmlns="http://www.w3.org/2000/svg">
              <defs><linearGradient id="paint"><stop stop-color="#fff"/></linearGradient></defs>
              <style>
                .label { display:flex; align-items:center; justify-content:center; font-family:system-ui; font-size:16px; color:#333; background-color:rgba(255, 255, 255, 0.5); }
                .node { fill:url(#paint); stroke:#9370db; stroke-width:1px; }
              </style>
              <foreignObject><div xmlns="http://www.w3.org/1999/xhtml" class="label">Annie</div></foreignObject>
              <rect class="node"/>
            </svg>
            """

        let sanitized = try SVGSanitizer.sanitize(raw)

        #expect(sanitized.contains("display:flex"))
        #expect(sanitized.contains("font-family:system-ui"))
        #expect(sanitized.contains("background-color:rgba(255, 255, 255, 0.5)"))
        #expect(sanitized.contains("fill:url(#paint)"))
        #expect(sanitized.contains("stroke:#9370db"))
        #expect(sanitized.contains(">Annie</"))
    }
}
