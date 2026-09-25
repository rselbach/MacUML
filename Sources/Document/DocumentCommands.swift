import AppKit
import SwiftUI

enum DocumentSaveOperation {
    case save
    case saveAs

    @MainActor
    func perform(on document: NSDocument, prepare: () -> Void) {
        prepare()
        switch self {
        case .save: document.save(nil)
        case .saveAs: document.saveAs(nil)
        }
    }
}

struct DocumentCommands: Commands {
    @FocusedValue(\.formatDocument) private var formatDocument

    var body: some Commands {
        CommandGroup(replacing: .saveItem) {
            Button("Close") { NSApp.keyWindow?.performClose(nil) }
                .keyboardShortcut("w")
                .modifierKeyAlternate(.option) {
                    Button("Close All") {
                        NSDocumentController.shared.closeAllDocuments(
                            withDelegate: nil, didCloseAllSelector: nil, contextInfo: nil)
                    }
                    .keyboardShortcut("w", modifiers: [.command, .option])
                }
            Button("Save") { save(.save) }
                .keyboardShortcut("s")
                .disabled(formatDocument == nil)
            Button("Save As…") { save(.saveAs) }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(formatDocument == nil)
            Button("Duplicate") { currentDocument?.duplicate(nil) }
                .disabled(formatDocument == nil)
            Button("Rename…") { currentDocument?.rename(nil) }
                .disabled(formatDocument == nil)
            Button("Move To…") { currentDocument?.move(nil) }
                .disabled(formatDocument == nil)
            Button("Revert To Saved…") { currentDocument?.revertToSaved(nil) }
                .disabled(formatDocument == nil || currentDocument?.fileURL == nil)
            Button("Browse All Versions…") { currentDocument?.browseVersions(nil) }
                .disabled(formatDocument == nil || currentDocument?.fileURL == nil)
        }
    }

    private var currentDocument: NSDocument? { NSDocumentController.shared.currentDocument }

    private func save(_ operation: DocumentSaveOperation) {
        guard let document = currentDocument else { return }
        operation.perform(on: document) {
            if AppSettings.shared.autoFormatOnSave {
                formatDocument?()
            }
        }
    }
}
