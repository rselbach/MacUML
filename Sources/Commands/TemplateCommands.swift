import SwiftUI

struct NewTemplateCommands: Commands {
    @Environment(\.newDocument) private var newDocument

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Menu("New from Template") {
                ForEach(DiagramTemplate.allCases) { template in
                    Button(template.title) {
                        newDocument(MermaidDocument(text: template.source))
                    }
                    .accessibilityLabel("New \(template.title) diagram")
                }
            }
        }
    }
}

struct SyntaxHelpCommand: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("Mermaid Syntax Help") {
                openWindow(id: "syntax-help")
            }
            .keyboardShortcut("?", modifiers: .command)
        }
    }
}
