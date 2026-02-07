import AppKit

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

    private lazy var keywordPattern: NSRegularExpression? = {
        let pattern = "\\b(" + keywords.joined(separator: "|") + ")\\b"
        return try? NSRegularExpression(pattern: pattern, options: [])
    }()

    private lazy var patterns: [(NSRegularExpression, NSColor)] = {
        var result: [(NSRegularExpression, NSColor)] = []

        let patternDefs: [(String, NSColor)] = [
            ("%%[^\\n]*", commentColor),
            ("\"[^\"\\n]*\"", stringColor),
            ("'[^'\\n]*'", stringColor),
            ("\\|[^|]+\\|", stringColor),
            // Sequence diagram arrows and colon separator
            ("-->>|->>|--x|-x|--\\)|-\\)|:", arrowColor),
            // Flowchart arrows
            ("-->|==>|-.->|==>>|-.->>|--o|<-->|<--|<.->", arrowColor),
            ("---|===|\\.\\.\\.", arrowColor),
            ("\\[[^\\]]+\\]", nodeColor),
            ("\\([^)]+\\)", nodeColor),
            ("\\{[^}]+\\}", nodeColor),
            ("\\(\\([^)]+\\)\\)", nodeColor),
            ("\\[\\[[^\\]]+\\]\\]", nodeColor),
            ("%%\\{[^}]+\\}%%", directiveColor),
        ]

        for (pattern, color) in patternDefs {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                result.append((regex, color))
            }
        }
        return result
    }()

    func highlight(_ textStorage: NSTextStorage, in editedRange: NSRange? = nil) {
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

        textStorage.beginEditing()

        textStorage.removeAttribute(.foregroundColor, range: targetRange)
        textStorage.addAttribute(.foregroundColor, value: NSColor.textColor, range: targetRange)

        for (regex, color) in patterns {
            regex.enumerateMatches(in: text, options: [], range: targetRange) { match, _, _ in
                if let matchRange = match?.range {
                    textStorage.addAttribute(.foregroundColor, value: color, range: matchRange)
                }
            }
        }

        keywordPattern?.enumerateMatches(in: text, options: [], range: targetRange) { match, _, _ in
            if let matchRange = match?.range {
                textStorage.addAttribute(.foregroundColor, value: keywordColor, range: matchRange)
            }
        }

        textStorage.endEditing()
    }
}
