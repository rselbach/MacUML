import Foundation

enum MermaidRenderState: Equatable {
    case idle
    case rendering
    case ready
    case failure(String)
}

struct MermaidError: Equatable {
    let message: String
    let line: Int?
}

enum MermaidTheme: String, CaseIterable {
    case auto = "auto"
    case `default` = "default"
    case dark = "dark"
    case forest = "forest"
    case neutral = "neutral"
    case base = "base"
    
    var label: String {
        switch self {
        case .auto: return "Auto"
        case .default: return "Default"
        case .dark: return "Dark"
        case .forest: return "Forest"
        case .neutral: return "Neutral"
        case .base: return "Base"
        }
    }
}
