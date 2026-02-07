import SwiftUI
import AppKit
import Sparkle

class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    @Published var updaterController: SPUStandardUpdaterController?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }
}

@main
struct MacUMLApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @FocusedValue(\.renderer) private var renderer

    var body: some Scene {
        DocumentGroup(newDocument: MermaidDocument()) { file in
            DocumentView(document: file.$document)
        }
        .defaultSize(width: 900, height: 600)
        .commands {
            AboutCommand()
            CheckForUpdatesCommand(updater: appDelegate.updaterController?.updater)
            CommandGroup(after: .textEditing) {
                Button("Refresh Preview") {
                    renderer?.refreshCurrentSource()
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(renderer == nil)
            }

            CommandGroup(after: .toolbar) {
                Button("Zoom In") {
                    renderer?.zoomIn()
                }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(renderer == nil)

                Button("Zoom Out") {
                    renderer?.zoomOut()
                }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(renderer == nil)

                Button("Actual Size") {
                    renderer?.resetZoom()
                }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(renderer == nil)
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
