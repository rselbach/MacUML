import Foundation

/// Reads and writes the diagram theme in Mermaid YAML front matter.
///
/// Mermaid applies `config.theme` from front matter such as:
/// ```
/// ---
/// config:
///   theme: forest
/// ---
/// ```
/// Only block-style `config` mappings are edited; other front matter is preserved as written.
enum MermaidFrontMatter {
    /// Themes a document can store. `auto` is an app preference, not a Mermaid theme.
    static let documentThemes = MermaidTheme.allCases.filter { $0 != .auto }

    /// Returns the theme the document sets in its front matter, if any.
    static func theme(in source: String) -> MermaidTheme? {
        guard source.hasPrefix("---") else { return nil }
        let lines = source.components(separatedBy: "\n")
        guard let block = Block(lines: lines), let config = block.config, let index = config.themeLine else {
            return nil
        }
        var value = lines[index].trimmed.dropFirst("theme:".count).trimmingCharacters(in: .whitespaces)
        if let comment = value.range(of: " #") {
            value = String(value[..<comment.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        guard let theme = MermaidTheme(rawValue: value), theme != .auto else { return nil }
        return theme
    }

    /// Returns the source with its front matter theme set, or removed when `theme` is nil.
    ///
    /// Returns the source unchanged when the front matter uses an inline `config` value.
    static func settingTheme(_ theme: MermaidTheme?, in source: String) -> String {
        var lines = source.components(separatedBy: "\n")
        let themeLine = theme.map { "theme: \($0.rawValue)" }

        guard let block = Block(lines: lines) else {
            guard let themeLine else { return source }
            return (["---", "config:", "  " + themeLine, "---"] + lines).joined(separator: "\n")
        }
        if block.hasInlineConfig { return source }

        guard let config = block.config else {
            guard let themeLine else { return source }
            lines.insert(contentsOf: ["config:", "  " + themeLine], at: block.end)
            return lines.joined(separator: "\n")
        }

        switch (themeLine, config.themeLine) {
        case (let themeLine?, let index?):
            lines[index] = config.indent + themeLine
        case (let themeLine?, nil):
            lines.insert(config.indent + themeLine, at: config.line + 1)
        case (nil, let index?):
            lines.remove(at: index)
            var end = block.end - 1
            if config.childCount == 1 {
                lines.remove(at: config.line)
                end -= 1
            }
            // drop front matter that no longer holds anything
            if lines[1..<end].allSatisfy({ $0.trimmed.isEmpty }) {
                lines.removeSubrange(0...end)
            }
        case (nil, nil):
            return source
        }
        return lines.joined(separator: "\n")
    }

    private struct Block {
        /// Index of the closing `---` line.
        let end: Int
        let config: Config?
        let hasInlineConfig: Bool

        init?(lines: [String]) {
            guard lines.first?.trimmed == "---",
                let end = lines.indices.dropFirst().first(where: { lines[$0].trimmed == "---" })
            else { return nil }
            self.end = end

            let configLine = (1..<end).first { lines[$0].hasPrefix("config:") }
            guard let configLine else {
                config = nil
                hasInlineConfig = false
                return
            }
            let value = lines[configLine].dropFirst("config:".count).trimmed
            hasInlineConfig = !value.isEmpty && !value.hasPrefix("#")
            config = hasInlineConfig ? nil : Config(lines: lines, line: configLine, end: end)
        }
    }

    private struct Config {
        let line: Int
        let indent: String
        let themeLine: Int?
        let childCount: Int

        init(lines: [String], line: Int, end: Int) {
            self.line = line
            var children: [Int] = []
            for index in (line + 1)..<end {
                let text = lines[index]
                if text.trimmed.isEmpty { continue }
                guard text.first == " " || text.first == "\t" else { break }
                children.append(index)
            }
            indent = children.first.map { String(lines[$0].prefix { $0 == " " || $0 == "\t" }) } ?? "  "
            let indent = indent
            themeLine = children.first { index in
                lines[index].hasPrefix(indent) && lines[index].dropFirst(indent.count).hasPrefix("theme:")
            }
            childCount = children.count
        }
    }
}

extension StringProtocol {
    fileprivate var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
