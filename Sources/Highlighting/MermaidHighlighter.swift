import AppKit
import os

@MainActor
final class MermaidHighlighter {
    static let shared = MermaidHighlighter()

    private let keywords: Set<String> = [
        "flowchart", "graph", "sequenceDiagram", "classDiagram", "stateDiagram",
        "erDiagram", "gantt", "pie", "mindmap", "timeline", "gitGraph", "journey",
        "quadrantChart", "requirementDiagram", "C4Context", "C4Container", "C4Component",
        "C4Dynamic", "C4Deployment", "sankey", "xychart", "block", "packet", "architecture",
        "subgraph", "end", "participant", "actor", "loop", "alt", "else", "opt", "par",
        "critical", "break", "rect", "note", "over", "activate", "deactivate", "title",
        "section", "class", "state", "direction", "TB", "TD", "BT", "RL", "LR",
        "dateFormat", "axisFormat", "excludes", "includes", "todayMarker", "tickInterval"
    ]

    private let keywordColor = NSColor.systemPurple
    private let commentColor = NSColor.systemGreen
    private let stringColor = NSColor.systemRed
    private let arrowColor = NSColor.systemBlue
    private let nodeColor = NSColor.systemOrange
    private let directiveColor = NSColor.systemTeal
    private let logger = Logger(subsystem: "com.macuml", category: "highlighter")

    private lazy var keywordPattern: NSRegularExpression? = {
        let pattern = "\\b(" + keywords.joined(separator: "|") + ")\\b"

        do {
            return try NSRegularExpression(pattern: pattern, options: [])
        } catch {
            logger.error("Failed to compile Mermaid keyword regex: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }()

    private lazy var patterns: [(NSRegularExpression, NSColor)] = {
        var result: [(NSRegularExpression, NSColor)] = []

        let patternDefs: [(String, NSColor)] = [
            ("%%[^\\n]*", commentColor),
            ("\"[^\"\\n]*\"", stringColor),
            ("'[^'\\n]*'", stringColor),
            ("\\|[^|]+\\|", stringColor),
            ("-->>|->>|--x|-x|--\\)|-\\)|:", arrowColor),
            ("-->|==>|-.->|==>>|-.->>|--o|<-->|<--|<.->", arrowColor),
            ("---|===|\\.\\.\\.", arrowColor),
            ("\\[[^\\]]+\\]", nodeColor),
            ("\\([^)]+\\)", nodeColor),
            ("\\{[^}]+\\}", nodeColor),
            ("\\(\\([^)]+\\)\\)", nodeColor),
            ("\\[\\[[^\\]]+\\]\\]", nodeColor),
            ("%%\\{.+\\}%%", directiveColor),
        ]

        for (pattern, color) in patternDefs {
            do {
                let regex = try NSRegularExpression(pattern: pattern, options: [])
                result.append((regex, color))
            } catch {
                logger.error("Failed to compile Mermaid highlighting regex '\(pattern, privacy: .public)': \(error.localizedDescription, privacy: .public)")
            }
        }
        return result
    }()

    func highlight(_ textStorage: NSTextStorage, in editedRange: NSRange? = nil) async {
        let fullRange = NSRange(location: 0, length: textStorage.length)
        let text = textStorage.string
        let nsText = text as NSString
        let targetRange: NSRange

        if let editedRange,
           editedRange.location != NSNotFound,
           editedRange.location <= textStorage.length {
            let safeLength = min(editedRange.length, max(0, textStorage.length - editedRange.location))
            let safeEditedRange = NSRange(location: editedRange.location, length: safeLength)
            targetRange = nsText.lineRange(for: safeEditedRange)
        } else {
            targetRange = fullRange
        }

        let patterns = self.patterns
        let keywordPattern = self.keywordPattern
        let keywordColor = self.keywordColor

        let matches = await Task.detached {
            Self.computeMatches(
                text: text,
                range: targetRange,
                patterns: patterns,
                keywordPattern: keywordPattern,
                keywordColor: keywordColor
            )
        }.value

        textStorage.beginEditing()
        textStorage.removeAttribute(.foregroundColor, range: targetRange)
        textStorage.addAttribute(.foregroundColor, value: NSColor.textColor, range: targetRange)

        for match in matches {
            textStorage.addAttribute(.foregroundColor, value: match.color, range: match.range)
        }

        textStorage.endEditing()
    }

    private nonisolated static func computeMatches(
        text: String,
        range: NSRange,
        patterns: [(NSRegularExpression, NSColor)],
        keywordPattern: NSRegularExpression?,
        keywordColor: NSColor
    ) -> [HighlightMatch] {
        var matches: [HighlightMatch] = []

        for (regex, color) in patterns {
            regex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
                if let matchRange = match?.range {
                    matches.append(HighlightMatch(range: matchRange, color: color))
                }
            }
        }

        keywordPattern?.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            if let matchRange = match?.range {
                matches.append(HighlightMatch(range: matchRange, color: keywordColor))
            }
        }

        return matches
    }
}

private struct HighlightMatch {
    let range: NSRange
    let color: NSColor
}
