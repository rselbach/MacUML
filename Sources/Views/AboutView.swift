import SwiftUI
import Sparkle

private enum Constants {
    static let mainVStackSpacing: CGFloat = 16
    static let iconSize: CGFloat = 128
    static let dividerWidth: CGFloat = 200
    static let updateSectionSpacing: CGFloat = 12
    static let contentPadding: CGFloat = 32
    static let windowWidth: CGFloat = 300
}

struct AboutView: View {
    let updater: SPUUpdater?
    
    private let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    private let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    
    @State private var automaticallyChecks = false
    
    var body: some View {
        VStack(spacing: Constants.mainVStackSpacing) {
            if let iconImage = NSApp.applicationIconImage {
                Image(nsImage: iconImage)
                    .resizable()
                    .frame(width: Constants.iconSize, height: Constants.iconSize)
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
                    .frame(width: Constants.dividerWidth)
                
                VStack(spacing: Constants.updateSectionSpacing) {
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
                .frame(width: Constants.dividerWidth)
            
            Text("© 2025 Roberto Selbach")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(Constants.contentPadding)
        .frame(width: Constants.windowWidth)
        .onAppear {
            automaticallyChecks = updater?.automaticallyChecksForUpdates ?? false
        }
    }
}

#Preview {
    AboutView(updater: nil)
}
