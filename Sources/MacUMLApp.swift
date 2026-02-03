import SwiftUI
import AppKit
import Sparkle

class AppDelegate: NSObject, NSApplicationDelegate {
    var updaterController: SPUStandardUpdaterController?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        
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

    var body: some Scene {
        DocumentGroup(newDocument: MermaidDocument()) { file in
            DocumentView(document: file.$document)
        }
        .commands {
            AboutCommand()
            CheckForUpdatesCommand(updater: appDelegate.updaterController?.updater)
            CommandGroup(after: .textEditing) {
                Button("Refresh Preview") {
                    NotificationCenter.default.post(name: .refreshPreview, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
        
        Settings {
            SettingsView()
        }
        
        Window("About MacUML", id: "about") {
            AboutView(updater: appDelegate.updaterController?.updater)
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

extension Notification.Name {
    static let refreshPreview = Notification.Name("refreshPreview")
}
