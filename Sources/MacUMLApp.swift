import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
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
            CommandGroup(after: .textEditing) {
                Button("Refresh Preview") {
                    NotificationCenter.default.post(name: .refreshPreview, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}

extension Notification.Name {
    static let refreshPreview = Notification.Name("refreshPreview")
}
