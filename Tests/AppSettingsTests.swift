import AppKit
import Testing

@testable import MacUML

@Suite("Editor Settings")
@MainActor
struct AppSettingsTests {
    @Test("Missing fonts resolve to a selectable system font")
    func missingFont() throws {
        let suite = "MacUMLTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("Greendale Missing Font", forKey: "editorFontFamily")
        let settings = AppSettings(defaults: defaults)
        #expect(settings.editorFontFamily == AppSettings.systemFontFamily)
        #expect(settings.editorFont == NSFont.monospacedSystemFont(ofSize: 13, weight: .regular))
        #expect(defaults.string(forKey: "editorFontFamily") == AppSettings.systemFontFamily)
    }

    @Test("An installed font preference survives validation")
    func installedFont() throws {
        let family = try #require(AppSettings.monospaceFonts.first)
        let suite = "MacUMLTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(family, forKey: "editorFontFamily")
        defaults.set(17.0, forKey: "editorFontSize")
        let settings = AppSettings(defaults: defaults)
        #expect(settings.editorFontFamily == family)
        #expect(settings.editorFont.pointSize == 17)
    }

    @Test("Invalid font sizes are bounded", arguments: [-20.0, 1000.0, Double.infinity])
    func invalidSize(_ size: Double) throws {
        let suite = "MacUMLTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(size, forKey: "editorFontSize")
        let settings = AppSettings(defaults: defaults)
        #expect(AppSettings.fontSizeRange.contains(settings.editorFontSize))
        #expect(AppSettings.fontSizeRange.contains(settings.editorFont.pointSize))
    }
}
