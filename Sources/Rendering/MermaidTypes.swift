import Foundation

/// Represents the current state of diagram rendering.
enum MermaidRenderState: Equatable {
    /// No diagram is loaded or the source is empty.
    case idle
    /// A render operation is in progress.
    case rendering
    /// Rendering completed successfully.
    case ready
    /// Rendering failed with an error message and optional line number.
    case failure(message: String, line: Int? = nil)
    
    var error: MermaidError? {
        if case .failure(let message, let line) = self {
            return MermaidError(message: message, line: line)
        }
        return nil
    }
}

/// An error from Mermaid.js diagram parsing or rendering.
struct MermaidError: Equatable {
    /// Human-readable error description.
    let message: String
    /// Line number where the error occurred, if available.
    let line: Int?
}

/// Available Mermaid.js diagram themes.
enum MermaidTheme: String, CaseIterable {
    /// Matches system appearance (light/dark mode).
    case auto = "auto"
    /// Default Mermaid theme.
    case `default` = "default"
    /// Dark theme for dark mode interfaces.
    case dark = "dark"
    /// Forest theme with green tones.
    case forest = "forest"
    /// Neutral theme with muted colors.
    case neutral = "neutral"
    /// Base theme for custom styling.
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
