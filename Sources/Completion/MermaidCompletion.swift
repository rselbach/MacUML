import Foundation

/// Suggestions that complete the word before the caret.
///
/// The first word of the declaration line offers diagram types, and the first word of a later line offers the
/// statements of the declared diagram, such as `participant` in a sequence diagram. Every word also offers the
/// words already in the document, so node and participant names complete after their first use.
enum MermaidCompletion {
    private static let logger = Logging.logger(category: "completion")

    /// Suggestions for the partial word before the caret.
    struct Completions: Equatable {
        /// The partial word that a suggestion replaces.
        let range: NSRange
        let suggestions: [String]
    }

    /// Diagram types that Mermaid recognizes in a declaration, most common first.
    static let diagramTypes = [
        "flowchart", "sequenceDiagram", "classDiagram", "stateDiagram-v2", "erDiagram", "gantt", "pie", "mindmap",
        "timeline", "gitGraph", "journey", "quadrantChart", "requirementDiagram", "C4Context", "C4Container",
        "C4Component", "C4Dynamic", "C4Deployment", "sankey", "xychart", "block", "packet", "architecture-beta",
        "kanban", "radar-beta", "treemap", "graph",
    ]

    private static let flowchartStatements = [
        "subgraph", "end", "direction", "classDef", "class", "style", "linkStyle", "click",
    ]
    private static let stateStatements = ["state", "note", "end", "direction", "classDef", "class", "style", "click"]

    // keyed by the first word of the diagram declaration, most common first
    private static let statements: [String: [String]] = [
        "flowchart": flowchartStatements,
        "graph": flowchartStatements,
        "sequenceDiagram": [
            "participant", "actor", "Note", "loop", "alt", "else", "opt", "par", "and", "critical", "option", "break",
            "rect", "box", "end", "activate", "deactivate", "autonumber", "create", "destroy", "link", "links", "title",
        ],
        "classDiagram": [
            "class", "namespace", "note", "direction", "classDef", "cssClass", "style", "click", "link", "callback",
        ],
        "stateDiagram": stateStatements,
        "stateDiagram-v2": stateStatements,
        "erDiagram": ["direction", "classDef", "class", "style"],
        "gantt": [
            "title", "dateFormat", "axisFormat", "tickInterval", "section", "excludes", "includes", "weekday",
            "weekend", "todayMarker", "inclusiveEndDates", "topAxis", "click",
        ],
        "pie": ["title"],
        "timeline": ["title", "section"],
        "journey": ["title", "section"],
        "gitGraph": ["commit", "branch", "checkout", "switch", "merge", "cherry-pick"],
    ]

    /// Suggestions for the partial word that ends at `caret`.
    ///
    /// Returns nil when the caret is inside a word, the partial word is shorter than `minimumLength`, or no
    /// suggestion extends it.
    static func completions(in text: NSString, at caret: Int, minimumLength: Int = 0) -> Completions? {
        if caret < text.length {
            let next = text.substring(with: text.rangeOfComposedCharacterSequence(at: caret))
            if next.first.map(isWordCharacter) == true { return nil }
        }
        let lineStart = text.lineRange(for: NSRange(location: caret, length: 0)).location
        let linePrefix = text.substring(with: NSRange(location: lineStart, length: caret - lineStart))
        let partial = String(linePrefix.reversed().prefix { isWordCharacter($0) || $0 == "-" }.reversed())
        guard partial.count >= minimumLength, partial.first.map(startsWord) ?? true else { return nil }

        let range = NSRange(location: caret - partial.utf16.count, length: partial.utf16.count)
        let prefix = partial.lowercased()
        let extendsPartial = { (candidate: String) in
            candidate.count > partial.count && candidate.lowercased().hasPrefix(prefix)
        }
        let keywords = keywords(at: range.location, lineStart: lineStart, in: text).filter(extendsPartial)
        // one-letter words are mostly arrowheads, such as the o in --o
        let words = documentWords(startingWith: partial, in: text)
            .filter { $0.count > 1 && extendsPartial($0) && !keywords.contains($0) }
            .sorted { $0.caseInsensitiveCompare($1) == .orderedAscending }
        let suggestions = keywords + words
        return suggestions.isEmpty ? nil : Completions(range: range, suggestions: suggestions)
    }

    /// Diagram types or statements for a word at `location`, which must be the first word of its line.
    private static func keywords(at location: Int, lineStart: Int, in text: NSString) -> [String] {
        let indent = text.substring(with: NSRange(location: lineStart, length: location - lineStart))
        guard indent.allSatisfy({ $0 == " " || $0 == "\t" }) else { return [] }
        guard let declaration = MermaidDeclaration(in: text) else {
            // the first line of an otherwise empty document will hold the declaration
            return text.substring(to: lineStart).allSatisfy(\.isWhitespace) ? diagramTypes : []
        }
        if lineStart == declaration.lineRange.location { return diagramTypes }
        guard lineStart > declaration.lineRange.location else { return [] }
        return statements[declaration.keyword] ?? []
    }

    /// Words in the document that start with `prefix`, ignoring case.
    ///
    /// A word starts with a letter or underscore and continues through letters, digits, and underscores. A hyphen
    /// joins the parts of a word such as `cherry-pick`, but two hyphens belong to a link such as `-->`.
    private static func documentWords(startingWith prefix: String, in text: NSString) -> Set<String> {
        let start = prefix.isEmpty ? "[\\p{L}_]" : NSRegularExpression.escapedPattern(for: prefix)
        let pattern = "(?<!\\w)(?<!\\w-)\(start)\\w*(?:-\\w+)*"
        let regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        } catch {
            logger.error("Failed to compile Mermaid completion regex: \(error.localizedDescription, privacy: .public)")
            return []
        }
        var words = Set<String>()
        regex.enumerateMatches(in: text as String, range: NSRange(location: 0, length: text.length)) { match, _, _ in
            guard let match else { return }
            words.insert(text.substring(with: match.range))
        }
        return words
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }

    private static func startsWord(_ character: Character) -> Bool {
        character.isLetter || character == "_"
    }
}
