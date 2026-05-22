import Foundation

/// Formats Mermaid diagram source code with consistent styling.
///
/// Features:
/// - Removes trailing whitespace
/// - Collapses consecutive blank lines
/// - Ensures a single newline at the end of non-empty files
/// - Preserves Mermaid syntax exactly otherwise
struct MermaidFormatter {
    /// Formats the given Mermaid source code.
    /// - Parameter source: The raw Mermaid diagram source
    /// - Returns: Formatted source code
    static func format(_ source: String) -> String {
        let normalizedLineEndings = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var lines = normalizedLineEndings
            .components(separatedBy: "\n")
            .map { $0.trailingWhitespaceTrimmed() }

        while lines.last?.isEmpty == true {
            lines.removeLast()
        }

        lines = collapseConsecutiveEmptyLines(lines)

        guard !lines.isEmpty else {
            return ""
        }

        return lines.joined(separator: "\n") + "\n"
    }

    /// Collapses consecutive empty lines to a single empty line
    private static func collapseConsecutiveEmptyLines(_ lines: [String]) -> [String] {
        var result: [String] = []
        var lastWasEmpty = false
        
        for line in lines {
            let isEmpty = line.trimmingCharacters(in: .whitespaces).isEmpty
            
            if isEmpty {
                if !lastWasEmpty {
                    result.append("")
                    lastWasEmpty = true
                }
            } else {
                result.append(line)
                lastWasEmpty = false
            }
        }
        
        return result
    }
}

private extension String {
    func trailingWhitespaceTrimmed() -> String {
        String(reversed().drop(while: \.isWhitespace).reversed())
    }
}
