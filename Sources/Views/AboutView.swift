import SwiftUI
import Sparkle

struct AboutView: View {
    let updater: SPUUpdater?
    
    private let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    private let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    
    @State private var automaticallyChecks = false
    
    var body: some View {
        VStack(spacing: 16) {
            if let iconURL = Bundle.module.url(forResource: "AppIcon", withExtension: "icns"),
               let iconImage = NSImage(contentsOf: iconURL) {
                Image(nsImage: iconImage)
                    .resizable()
                    .frame(width: 128, height: 128)
            }
            
            Text("MacUML")
                .font(.title)
                .fontWeight(.semibold)
            
            Text("Version \(appVersion) (\(buildNumber))")
                .font(.callout)
                .foregroundStyle(.secondary)
            
            Text("A native macOS editor for Mermaid diagrams")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            if updater != nil {
                Divider()
                    .frame(width: 200)
                
                VStack(spacing: 12) {
                    Toggle("Check for updates automatically", isOn: $automaticallyChecks)
                        .toggleStyle(.checkbox)
                        .onChange(of: automaticallyChecks) { _, newValue in
                            updater?.automaticallyChecksForUpdates = newValue
                        }
                    
                    Button("Check for Updates…") {
                        updater?.checkForUpdates()
                    }
                    .disabled(updater?.canCheckForUpdates != true)
                }
            }
            
            Divider()
                .frame(width: 200)
            
            Text("© 2025 Roberto Selbach")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(32)
        .frame(width: 300)
        .onAppear {
            automaticallyChecks = updater?.automaticallyChecksForUpdates ?? false
        }
    }
}

#Preview {
    AboutView(updater: nil)
}
