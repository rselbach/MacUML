import SwiftUI

private enum Constants {
    static let fontSizeLabelWidth: CGFloat = 45
    static let windowWidth: CGFloat = 400
    static let windowHeight: CGFloat = 420
}

struct SettingsView: View {
    @StateObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section("Source Editor") {
                Picker("Font Family:", selection: $settings.editorFontFamily) {
                    Text(AppSettings.systemFontFamily).tag(AppSettings.systemFontFamily)
                    ForEach(AppSettings.monospaceFonts, id: \.self) { fontName in
                        Text(fontName)
                            .font(.custom(fontName, size: 12))
                            .tag(fontName)
                    }
                }
                .pickerStyle(.menu)

                HStack {
                    Text("Font Size:")
                    Slider(value: $settings.editorFontSize, in: AppSettings.fontSizeRange, step: 1)
                        .accessibilityLabel("Editor font size")
                    Text("\(Int(settings.editorFontSize)) pt")
                        .monospacedDigit()
                        .frame(width: Constants.fontSizeLabelWidth, alignment: .trailing)
                }

                Toggle("Show Line Numbers", isOn: $settings.showLineNumbers)

                Toggle("Format when choosing Save or Save As", isOn: $settings.autoFormatOnSave)
                    .help("Clean up whitespace before explicit Save commands. Autosave preserves your typing.")
            }

            Section("Diagram Preview") {
                Picker("Default Theme:", selection: $settings.defaultDiagramTheme) {
                    ForEach(MermaidTheme.allCases, id: \.self) { theme in
                        Text(theme.label).tag(theme)
                    }
                }
                .pickerStyle(.menu)
                .help("Used when a document doesn't set a theme in its front matter.")
            }

            Section("Export") {
                Picker("Background:", selection: $settings.exportBackground) {
                    ForEach(ExportBackground.allCases, id: \.self) { background in
                        Text(background.label).tag(background)
                    }
                }
                .pickerStyle(.menu)
                .help("Theme Color matches the preview so dark themes stay readable.")

                Picker("PNG Scale:", selection: $settings.pngExportScale) {
                    ForEach(AppSettings.pngExportScales, id: \.self) { scale in
                        Text("\(scale)×").tag(scale)
                    }
                }
                .pickerStyle(.menu)
                .help("2× and 3× keep exported PNGs sharp on Retina displays and in slides.")
            }
        }
        .formStyle(.grouped)
        .frame(width: Constants.windowWidth, height: Constants.windowHeight)
    }
}

#Preview {
    SettingsView()
}
