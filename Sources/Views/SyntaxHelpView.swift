import SwiftUI

struct SyntaxHelpView: View {
    private let examples = DiagramTemplate.allCases.filter { $0 != .blank }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Mermaid syntax")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Choose a template from File, then edit its Mermaid source. The preview updates as you type.")
                        .foregroundStyle(.secondary)
                }

                ForEach(examples) { example in
                    SyntaxExampleView(example: example)
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Keyboard commands")
                        .font(.headline)

                    KeyboardCommandRow(title: "Format Document", shortcut: "⌘⇧F")
                    Text("Format Document cleans up whitespace. It preserves Mermaid syntax.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    KeyboardCommandRow(title: "Toggle Comment", shortcut: "⌘/")
                    KeyboardCommandRow(title: "Refresh Preview", shortcut: "⌘R")
                    KeyboardCommandRow(title: "Zoom In", shortcut: "⌘+")
                    KeyboardCommandRow(title: "Zoom Out", shortcut: "⌘−")
                    KeyboardCommandRow(title: "Fit to Window", shortcut: "⌘0")
                    KeyboardCommandRow(title: "Editor / Split / Preview", shortcut: "⌘1 / ⌘2 / ⌘3")
                    KeyboardCommandRow(title: "Export PNG", shortcut: "⌘⇧E")
                    KeyboardCommandRow(title: "Copy SVG", shortcut: "⌘⇧C")
                    Text(
                        "Scroll to pan. Pinch or hold Option while scrolling to zoom. Fit to Window shrinks large diagrams to the window; 100% is actual size."
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    Text(
                        "Pause Live Preview while editing a large document, then use Refresh Preview. Export includes the complete diagram and requires a current preview."
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    Text(
                        "The optional Save formatting setting applies to Save and Save As. Autosave preserves in-progress typing."
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 640, minHeight: 600)
        .accessibilityLabel("Mermaid syntax help")
    }
}

private struct SyntaxExampleView: View {
    let example: DiagramTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(example.title)
                .font(.headline)
            Text(example.source)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(example.title) syntax example")
    }
}

private struct KeyboardCommandRow: View {
    let title: String
    let shortcut: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(shortcut)
                .font(.body.monospaced())
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
