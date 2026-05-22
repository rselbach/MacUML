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
    private let logger = Logging.logger(category: "highlighter")

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
        let patternDefs: [(String, NSColor)] = [
            ("%%\\{.+\\}%%", directiveColor),
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
        ]

        return patternDefs.compactMap { pattern, color in
            do {
                return (try NSRegularExpression(pattern: pattern, options: []), color)
            } catch {
                logger.error("Failed to compile Mermaid highlighting regex '\(pattern, privacy: .public)': \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
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

        guard !Task.isCancelled else { return }

        // Chunk application of attributes to avoid blocking the main thread for large files
        let chunkSize = 500
        var i = 0
        
        textStorage.beginEditing()
        // If text length changed drastically (e.g. user pasted), targetRange might be out of bounds. 
        // We clamp it safely.
        let safeTargetRange = targetRange.clamped(to: textStorage.length) ?? NSRange(location: 0, length: textStorage.length)
        textStorage.removeAttribute(.foregroundColor, range: safeTargetRange)
        textStorage.addAttribute(.foregroundColor, value: NSColor.textColor, range: safeTargetRange)

        for match in matches {
            guard !Task.isCancelled else { break }
            if let safeMatchRange = match.range.clamped(to: textStorage.length) {
                textStorage.addAttribute(.foregroundColor, value: match.color, range: safeMatchRange)
            }
            
            i += 1
            if i % chunkSize == 0 {
                textStorage.endEditing()
                await Task.yield()
                textStorage.beginEditing()
            }
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
        var claimedIndexes = IndexSet()

        func appendMatch(_ range: NSRange, color: NSColor) {
            let upperBound = NSMaxRange(range)
            guard range.location >= 0, range.length > 0, upperBound > range.location else {
                return
            }

            let integerRange = range.location..<upperBound
            guard !claimedIndexes.intersects(integersIn: integerRange) else {
                return
            }

            matches.append(HighlightMatch(range: range, color: color))
            claimedIndexes.insert(integersIn: integerRange)
        }

        for (regex, color) in patterns {
            regex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
                guard let matchRange = match?.range else { return }
                appendMatch(matchRange, color: color)
            }
        }

        keywordPattern?.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            guard let matchRange = match?.range else { return }
            appendMatch(matchRange, color: keywordColor)
        }

        return matches
    }
}

private struct HighlightMatch {
    let range: NSRange
    let color: NSColor
}
