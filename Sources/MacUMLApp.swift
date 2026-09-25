import AppKit
import Sparkle
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    @Published var updaterController: SPUStandardUpdaterController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if !DEBUG
            updaterController = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
        #endif
    }
}

@main
struct MacUMLApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @FocusedValue(\.formatDocument) private var formatDocument

    var body: some Scene {
        DocumentGroup(newDocument: MermaidDocument()) { file in
            DocumentView(document: file.$document, fileURL: file.fileURL)
        }
        .defaultSize(width: 900, height: 600)
        .commands {
            ExportCommands()
            PreviewCommands()
            NewTemplateCommands()
            SyntaxHelpCommand()
            AboutCommand()
            DocumentCommands()
            CheckForUpdatesCommand(updater: appDelegate.updaterController?.updater)
            CommandGroup(after: .textEditing) {
                Button("Format Document") {
                    formatDocument?()
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .disabled(formatDocument == nil)
            }
        }

        Settings {
            SettingsView()
        }

        Window("About MacUML", id: "about") {
            AboutWindowContent()
                .environmentObject(appDelegate)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Window("Mermaid Syntax Help", id: "syntax-help") {
            SyntaxHelpView()
        }
        .defaultSize(width: 700, height: 700)
    }
}

struct AboutCommand: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About MacUML") {
                openWindow(id: "about")
            }
        }
    }
}

struct CheckForUpdatesCommand: Commands {
    let updater: SPUUpdater?

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            if let updater {
                Button("Check for Updates…") {
                    updater.checkForUpdates()
                }
                .disabled(!updater.canCheckForUpdates)
            }
        }
    }
}

struct AboutWindowContent: View {
    @EnvironmentObject private var appDelegate: AppDelegate

    var body: some View {
        AboutView(updater: appDelegate.updaterController?.updater)
    }
}

struct FocusedRendererKey: FocusedValueKey {
    typealias Value = MermaidRenderer
}

extension FocusedValues {
    var renderer: MermaidRenderer? {
        get { self[FocusedRendererKey.self] }
        set { self[FocusedRendererKey.self] = newValue }
    }
}

struct FocusedFormatDocumentKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var formatDocument: (() -> Void)? {
        get { self[FocusedFormatDocumentKey.self] }
        set { self[FocusedFormatDocumentKey.self] = newValue }
    }
}
