import Testing
@testable import MacUML

@Suite("Mermaid Types Tests")
struct MermaidTypesTests {
    @Test("All themes have labels")
    func allThemesHaveLabels() {
        for theme in MermaidTheme.allCases {
            #expect(!theme.label.isEmpty)
        }
    }

    @Test("Theme raw values match expected strings")
    func themeRawValues() {
        #expect(MermaidTheme.auto.rawValue == "auto")
        #expect(MermaidTheme.default.rawValue == "default")
        #expect(MermaidTheme.dark.rawValue == "dark")
        #expect(MermaidTheme.forest.rawValue == "forest")
        #expect(MermaidTheme.neutral.rawValue == "neutral")
        #expect(MermaidTheme.base.rawValue == "base")
    }

    @Test("Theme labels are capitalized")
    func themeLabelsCapitalized() {
        for theme in MermaidTheme.allCases {
            let expected = theme.rawValue.capitalized
            #expect(theme.label == expected)
        }
    }

    @Test("Theme count is 6")
    func themeCount() {
        #expect(MermaidTheme.allCases.count == 6)
    }

    @Test("Error message extraction")
    func errorMessageExtraction() {
        let error = MermaidError(message: "Syntax error on line 5", line: 5)
        #expect(error.message == "Syntax error on line 5")
        #expect(error.line == 5)
    }

    @Test("Error without line number")
    func errorWithoutLine() {
        let error = MermaidError(message: "Unknown error", line: nil)
        #expect(error.message == "Unknown error")
        #expect(error.line == nil)
    }

    @Test("Render state idle case")
    func renderStateIdle() {
        if case .idle = MermaidRenderState.idle {
            // Expected
        } else {
            Issue.record("Expected idle state")
        }
    }

    @Test("Render state ready case")
    func renderStateReady() {
        if case .ready = MermaidRenderState.ready {
            // Expected
        } else {
            Issue.record("Expected ready state")
        }
    }

    @Test("Render state rendering case")
    func renderStateRendering() {
        if case .rendering = MermaidRenderState.rendering {
            // Expected
        } else {
            Issue.record("Expected rendering state")
        }
    }

    @Test("Render state failure with line")
    func renderStateFailureWithLine() {
        let state = MermaidRenderState.failure(error: MermaidError(message: "Parse error", line: 10))
        if case .failure(let error) = state {
            #expect(error.message == "Parse error")
            #expect(error.line == 10)
        } else {
            Issue.record("Expected failure state")
        }
    }

    @Test("Render state failure without line")
    func renderStateFailureWithoutLine() {
        let state = MermaidRenderState.failure(error: MermaidError(message: "Generic error", line: nil))
        if case .failure(let error) = state {
            #expect(error.message == "Generic error")
            #expect(error.line == nil)
        } else {
            Issue.record("Expected failure state")
        }
    }
}
