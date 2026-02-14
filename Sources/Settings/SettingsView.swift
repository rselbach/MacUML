import SwiftUI

private enum Constants {
    static let fontSizeRange: ClosedRange<Double> = 9...24
    static let fontSizeLabelWidth: CGFloat = 45
    static let windowWidth: CGFloat = 400
    static let windowHeight: CGFloat = 300
}

struct SettingsView: View {
    @StateObject private var settings = AppSettings.shared
    
    var body: some View {
        Form {
            Section("Source Editor") {
                Picker("Font Family:", selection: $settings.editorFontFamily) {
                    ForEach(AppSettings.monospaceFonts, id: \.self) { fontName in
                        Text(fontName)
                            .font(.custom(fontName, size: 12))
                            .tag(fontName)
                    }
                }
                .pickerStyle(.menu)
                
                HStack {
                    Text("Font Size:")
                    Slider(value: $settings.editorFontSize, in: Constants.fontSizeRange, step: 1)
                    Text("\(Int(settings.editorFontSize)) pt")
                        .monospacedDigit()
                        .frame(width: Constants.fontSizeLabelWidth, alignment: .trailing)
                }
                
                Toggle("Show Line Numbers", isOn: $settings.showLineNumbers)
            }
            
            Section("Diagram Preview") {
                Picker("Default Theme:", selection: $settings.defaultDiagramTheme) {
                    ForEach(MermaidTheme.allCases, id: \.self) { theme in
                        Text(theme.label).tag(theme)
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .formStyle(.grouped)
        .frame(width: Constants.windowWidth, height: Constants.windowHeight)
    }
}

#Preview {
    SettingsView()
}
