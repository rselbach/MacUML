import Testing

@testable import MacUML

@Suite("Mermaid Front Matter Tests")
struct MermaidFrontMatterTests {
    private static let diagram = "flowchart TD\n    Troy --> Abed\n"

    @Test(
        "Reads the document theme",
        arguments: [
            (diagram, nil),
            ("---\nconfig:\n  theme: forest\n---\n" + diagram, MermaidTheme.forest),
            ("---\ntitle: Greendale\nconfig:\n    look: classic\n    theme: \"dark\" # night\n---\n" + diagram, .dark),
            ("---\nconfig:\n  flowchart:\n    theme: dark\n---\n" + diagram, nil),
            ("---\nconfig:\n  theme: auto\n---\n" + diagram, nil),
            ("---\nconfig: {theme: dark}\n---\n" + diagram, nil),
        ] as [(String, MermaidTheme?)])
    func readsTheme(source: String, want: MermaidTheme?) {
        #expect(MermaidFrontMatter.theme(in: source) == want)
    }

    @Test(
        "Sets the document theme",
        arguments: [
            (diagram, MermaidTheme.dark, "---\nconfig:\n  theme: dark\n---\n" + diagram),
            ("---\ntitle: Troy\n---\n" + diagram, .neutral, "---\ntitle: Troy\nconfig:\n  theme: neutral\n---\n" + diagram),
            (
                "---\nconfig:\n    look: handDrawn\n---\n" + diagram, .forest,
                "---\nconfig:\n    theme: forest\n    look: handDrawn\n---\n" + diagram
            ),
            ("---\nconfig:\n  theme: dark\n---\n" + diagram, .base, "---\nconfig:\n  theme: base\n---\n" + diagram),
            ("---\nconfig: {look: neo}\n---\n" + diagram, .dark, "---\nconfig: {look: neo}\n---\n" + diagram),
        ] as [(String, MermaidTheme, String)])
    func setsTheme(source: String, theme: MermaidTheme, want: String) {
        let result = MermaidFrontMatter.settingTheme(theme, in: source)
        #expect(result == want)
        if result != source {
            #expect(MermaidFrontMatter.theme(in: result) == theme)
        }
    }

    @Test(
        "Removing the theme drops front matter that becomes empty",
        arguments: [
            ("---\nconfig:\n  theme: dark\n---\n" + diagram, diagram),
            ("---\ntitle: Troy\nconfig:\n  theme: dark\n---\n" + diagram, "---\ntitle: Troy\n---\n" + diagram),
            (
                "---\nconfig:\n  theme: dark\n  look: neo\n---\n" + diagram,
                "---\nconfig:\n  look: neo\n---\n" + diagram
            ),
            (diagram, diagram),
        ])
    func removesTheme(source: String, want: String) {
        #expect(MermaidFrontMatter.settingTheme(nil, in: source) == want)
    }
}
