import SwiftUI
import AppKit

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    
    private static let defaultFontFamily = "SF Mono"
    
    @AppStorage("editorFontSize") var editorFontSize: Double = 13
    @AppStorage("editorFontFamily") var editorFontFamily: String = defaultFontFamily
    @AppStorage("showLineNumbers") var showLineNumbers: Bool = true
    @AppStorage("defaultDiagramTheme") var defaultDiagramTheme: MermaidTheme = .auto
    
    private init() {
        if UserDefaults.standard.string(forKey: "editorFontFamily") == nil {
            UserDefaults.standard.set(Self.defaultFontFamily, forKey: "editorFontFamily")
        }
    }
    
    var editorFont: NSFont {
        if let font = NSFont(name: editorFontFamily, size: editorFontSize) {
            return font
        }
        return NSFont.monospacedSystemFont(ofSize: editorFontSize, weight: .regular)
    }
    
    static let monospaceFonts: [String] = {
        let monoFamilies = NSFontManager.shared.availableFontFamilies.filter { family in
            guard let font = NSFont(name: family, size: 12) else { return false }
            return font.isFixedPitch || family.lowercased().contains("mono") || family.lowercased().contains("courier") || family.lowercased().contains("menlo") || family.lowercased().contains("consolas")
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
