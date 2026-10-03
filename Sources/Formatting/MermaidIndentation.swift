import Foundation

/// Block-aware indentation for Mermaid source.
///
/// Return indents the line after the diagram declaration or a block opener such as `subgraph`, `loop`, or a
/// trailing `{`. Closers (`end`, `}`) and dividers (`else`, `and`, `option`) realign with the line that opened
/// their block, and a Gantt, journey, or timeline `section` realigns with the previous section. A keyword
/// realigns only once it is complete, so a node named `options` or `endpoint` keeps its place.
enum MermaidIndentation {
    /// One level of indentation.
    static let unit = "    "

    /// A replacement for the leading whitespace of a line.
    struct Realignment: Equatable {
        let range: NSRange
        let indent: String
    }

    /// Indentation for Return at `caret`: an optional realignment of the caret's line, then the new line's indent.
    static func newline(in text: NSString, at caret: Int) -> (realignment: Realignment?, indent: String) {
        let line = Line(in: text, at: caret)
        guard let header = header(in: text), line.start >= header.lineRange.location else {
            return (nil, line.indent)
        }
        if line.start == header.lineRange.location {
            return (nil, line.indent + unit)
        }

        let role = role(of: line.content, in: header.vocabulary)
        switch role {
        case .opener:
            return (nil, line.indent + unit)
        case .plain:
            return (nil, line.indent)
        case .closer, .divider, .section:
            let target = targetIndent(for: role, above: line.start, in: text, header: header) ?? line.indent
            let realignment = target == line.indent ? nil : line.realignment(to: target)
            return (realignment, role == .closer ? target : target + unit)
        }
    }

    /// Realignment of the caret's line after typing a space or `}` that completes a closing keyword.
    static func realignment(afterTypingIn text: NSString, at caret: Int) -> Realignment? {
        let line = Line(in: text, at: caret)
        let typed = line.prefix.drop { $0 == " " || $0 == "\t" }
        let word = typed.dropLast()
        let isComplete = typed == "}" || (typed.last == " " && !word.isEmpty && !word.contains(where: \.isWhitespace))
        guard isComplete, let header = header(in: text), line.start > header.lineRange.location else { return nil }

        let role = role(of: line.content, in: header.vocabulary)
        guard role == .closer || role == .divider || role == .section,
            let target = targetIndent(for: role, above: line.start, in: text, header: header),
            target != line.indent
        else { return nil }
        return line.realignment(to: target)
    }

    private enum Role {
        case opener
        case divider
        case closer
        case section
        case plain
    }

    /// Block keywords of the diagram type that the header declares.
    private struct Vocabulary {
        var openers: Set<String> = []
        var dividers: Set<String> = []
        var hasSections = false
    }

    // keyed by the first word of the diagram declaration; braces open and close blocks in every diagram
    private static let vocabularies: [String: Vocabulary] = [
        "flowchart": Vocabulary(openers: ["subgraph"]),
        "graph": Vocabulary(openers: ["subgraph"]),
        "sequenceDiagram": Vocabulary(
            openers: ["alt", "box", "break", "critical", "loop", "opt", "par", "par_over", "rect"],
            dividers: ["and", "else", "option"]),
        "gantt": Vocabulary(hasSections: true),
        "journey": Vocabulary(hasSections: true),
        "timeline": Vocabulary(hasSections: true),
    ]

    private struct Header {
        let lineRange: NSRange
        let vocabulary: Vocabulary
    }

    /// The caret's line up to the caret.
    private struct Line {
        let start: Int
        let prefix: String
        let indent: String
        let content: String

        init(in text: NSString, at caret: Int) {
            start = text.lineRange(for: NSRange(location: caret, length: 0)).location
            prefix = text.substring(with: NSRange(location: start, length: caret - start))
            indent = leadingWhitespace(of: prefix)
            content = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        func realignment(to target: String) -> Realignment {
            Realignment(range: NSRange(location: start, length: indent.utf16.count), indent: target)
        }
    }

    private static func header(in text: NSString) -> Header? {
        guard let declaration = MermaidDeclaration(in: text) else { return nil }
        return Header(lineRange: declaration.lineRange, vocabulary: vocabularies[declaration.keyword] ?? Vocabulary())
    }

    private static func role(of content: String, in vocabulary: Vocabulary) -> Role {
        if content.hasPrefix("%%") { return .plain }
        if content.hasPrefix("}") { return .closer }
        if content.hasSuffix("{") { return .opener }
        let keyword = String(content.prefix { !$0.isWhitespace })
        if vocabulary.openers.contains(keyword) { return .opener }
        if vocabulary.dividers.contains(keyword) { return .divider }
        if keyword == "end", !vocabulary.openers.isEmpty { return .closer }
        if keyword == "section", vocabulary.hasSections { return .section }
        return .plain
    }

    /// The indentation a closer, divider, or section aligns with, searching upward no further than the header.
    private static func targetIndent(
        for role: Role, above lineStart: Int, in text: NSString, header: Header
    ) -> String? {
        let lines = sequence(state: lineStart) { location -> String? in
            guard location > NSMaxRange(header.lineRange) else { return nil }
            let range = text.lineRange(for: NSRange(location: location - 1, length: 0))
            location = range.location
            return text.substring(with: range)
        }
        let classified = lines.lazy.map { line in
            (line: line, role: Self.role(of: line.trimmingCharacters(in: .whitespacesAndNewlines), in: header.vocabulary))
        }

        if role == .section {
            return classified.first { $0.role == .section }.map { leadingWhitespace(of: $0.line) }
        }
        var depth = 0
        for (line, lineRole) in classified {
            switch lineRole {
            case .closer:
                depth += 1
            case .opener where depth == 0:
                return leadingWhitespace(of: line)
            case .opener:
                depth -= 1
            case .divider, .section, .plain:
                continue
            }
        }
        return nil
    }

    private static func leadingWhitespace(of line: String) -> String {
        String(line.prefix { $0 == " " || $0 == "\t" })
    }
}
