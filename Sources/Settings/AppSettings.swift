import AppKit
import SwiftUI

/// Global application settings persisted via UserDefaults.
///
/// Settings include:
/// - Editor font family and size
/// - Line number visibility toggle
/// - Default diagram theme for new documents
///
/// Access via `AppSettings.shared`. Changes are automatically persisted.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    static let systemFontFamily = "System Monospaced"
    static let fontSizeRange: ClosedRange<Double> = 9...24

    @AppStorage("editorFontSize") var editorFontSize: Double = 13
    @AppStorage("editorFontFamily") var editorFontFamily: String = systemFontFamily
    @AppStorage("showLineNumbers") var showLineNumbers: Bool = true
    @AppStorage("defaultDiagramTheme") var defaultDiagramTheme: MermaidTheme = .auto
    @AppStorage("autoFormatOnSave") var autoFormatOnSave: Bool = false

    init(defaults: UserDefaults = .standard) {
        _editorFontSize = AppStorage(wrappedValue: 13, "editorFontSize", store: defaults)
        _editorFontFamily = AppStorage(wrappedValue: Self.systemFontFamily, "editorFontFamily", store: defaults)
        _showLineNumbers = AppStorage(wrappedValue: true, "showLineNumbers", store: defaults)
        _defaultDiagramTheme = AppStorage(wrappedValue: .auto, "defaultDiagramTheme", store: defaults)
        _autoFormatOnSave = AppStorage(wrappedValue: false, "autoFormatOnSave", store: defaults)
        if !Self.monospaceFonts.contains(editorFontFamily) {
            editorFontFamily = Self.systemFontFamily
        }
        editorFontSize = Self.validFontSize(editorFontSize)
    }

    var editorFont: NSFont {
        let size = Self.validFontSize(editorFontSize)
        if Self.monospaceFonts.contains(editorFontFamily),
            let font = NSFont(name: editorFontFamily, size: size)
        {
            return font
        }
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    private static func validFontSize(_ size: Double) -> Double {
        guard size.isFinite else { return 13 }
        return min(fontSizeRange.upperBound, max(fontSizeRange.lowerBound, size))
    }

    static let monospaceFonts: [String] = {
        let monoFamilies = NSFontManager.shared.availableFontFamilies.filter { family in
            guard let font = NSFont(name: family, size: 12) else { return false }
            return font.isFixedPitch || family.lowercased().contains("mono") || family.lowercased().contains("courier")
                || family.lowercased().contains("menlo") || family.lowercased().contains("consolas")
        }

        let preferred = ["SF Mono", "Menlo", "Monaco", "Courier New", "Courier"]
        let sorted = monoFamilies.sorted { a, b in
            let aIdx = preferred.firstIndex(of: a) ?? Int.max
            let bIdx = preferred.firstIndex(of: b) ?? Int.max
            if aIdx != bIdx { return aIdx < bIdx }
            return a < b
        }
        return sorted
    }()
}
