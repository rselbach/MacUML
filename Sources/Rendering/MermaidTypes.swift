import Foundation

/// Represents the current state of diagram rendering.
enum MermaidRenderState: Equatable {
    /// No diagram is loaded or the source is empty.
    case idle
    /// A render operation is in progress.
    case rendering
    /// Rendering completed successfully.
    case ready
    /// Rendering failed with an error.
    case failure(error: MermaidError)
    
    var error: MermaidError? {
        if case .failure(let error) = self {
            return error
        }
        return nil
    }
}

/// An error from Mermaid.js diagram parsing or rendering.
struct MermaidError: Equatable, LocalizedError {
    /// Human-readable error description.
    let message: String
    /// Line number where the error occurred, if available.
    let line: Int?

    var errorDescription: String? {
        if let line {
            return "Line \(line): \(message)"
        }
        return message
    }
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

    /// Human-readable display label for UI presentation.
    var label: String {
        rawValue.capitalized
    }
}
