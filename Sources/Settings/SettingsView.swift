import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    
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
                    Slider(value: $settings.editorFontSize, in: 9...24, step: 1)
                    Text("\(Int(settings.editorFontSize)) pt")
                        .monospacedDigit()
                        .frame(width: 45, alignment: .trailing)
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
        .frame(width: 400, height: 250)
    }
}

#Preview {
    SettingsView()
}
