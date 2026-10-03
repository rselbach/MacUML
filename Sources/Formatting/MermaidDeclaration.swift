import Foundation

/// The diagram declaration: the first line after front matter that is neither blank nor a comment.
struct MermaidDeclaration {
    let lineRange: NSRange
    /// The declaration's first word, such as `flowchart` or `stateDiagram-v2`.
    let keyword: String

    init?(in text: NSString) {
        var location = 0
        var inFrontMatter = false
        while location < text.length {
            let range = text.lineRange(for: NSRange(location: location, length: 0))
            let content = text.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
            location = NSMaxRange(range)
            if range.location == 0, content == "---" {
                inFrontMatter = true
            } else if inFrontMatter {
                inFrontMatter = content != "---"
            } else if !content.isEmpty, !content.hasPrefix("%%") {
                lineRange = range
                keyword = String(content.prefix { !$0.isWhitespace })
                return
            }
        }
        return nil
    }
}
