import Testing
@testable import MacUML

@Suite("SVG Sanitizer Tests")
struct SVGSanitizerTests {
    @Test("Removes script, foreignObject, and event handlers")
    func stripsScriptForeignObjectAndOnAttributes() throws {
        let raw = """
        <svg xmlns=\"http://www.w3.org/2000/svg\" onload=\"alert(1)\">
          <script>alert('x')</script>
          <foreignObject><div>bad</div></foreignObject>
          <g onclick=\"evil()\"><text>Hello</text></g>
        </svg>
        """

        let sanitized = try SVGSanitizer.sanitize(raw)

        #expect(!sanitized.localizedCaseInsensitiveContains("<script"))
        #expect(!sanitized.localizedCaseInsensitiveContains("<foreignObject"))
        #expect(!sanitized.localizedCaseInsensitiveContains("onload="))
        #expect(!sanitized.localizedCaseInsensitiveContains("onclick="))
        #expect(sanitized.contains("<text>Hello</text>"))
    }

    @Test("Removes unsafe URL references from attributes")
    func stripsUnsafeURLReferences() throws {
        let raw = """
        <svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\">
          <a href=\"javascript:alert(1)\"><text>link</text></a>
          <rect fill=\"url(http://evil.test/x)\"/>
          <use xlink:href=\"https://evil.test/symbol\"/>
        </svg>
        """

        let sanitized = try SVGSanitizer.sanitize(raw)

        #expect(!sanitized.localizedCaseInsensitiveContains("javascript:"))
        #expect(!sanitized.contains("url(http://evil.test/x)"))
        #expect(!sanitized.contains("https://evil.test/symbol"))
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
}
