import Foundation

enum SVGSanitizer {
    private static let blockedElements: Set<String> = [
        "script",
        "foreignobject"
    ]

    private static let urlReferenceAttributes: Set<String> = [
        "href",
        "xlink:href",
        "clip-path",
        "filter",
        "mask",
        "marker-start",
        "marker-mid",
        "marker-end",
        "fill",
        "stroke"
    ]

    static func sanitize(_ rawSVG: String) throws -> String {
        let data = Data(rawSVG.utf8)
        let document = try XMLDocument(data: data, options: [.nodePreserveAll])

        guard let root = document.rootElement(),
              root.name?.lowercased() == "svg" else {
            throw NSError(
                domain: "SVGSanitizer",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid SVG root element"]
            )
        }

        sanitizeElement(root)
        return document.xmlString(options: [.nodeCompactEmptyElement])
    }

    private static func sanitizeElement(_ element: XMLElement) {
        sanitizeAttributes(on: element)

        for child in element.children ?? [] {
            guard let childElement = child as? XMLElement,
                  let rawName = childElement.name else {
                continue
            }

            let elementName = rawName.lowercased()
            if blockedElements.contains(elementName) {
                child.detach()
                continue
            }

            sanitizeElement(childElement)
        }

        if element.name?.lowercased() == "style",
           let css = element.stringValue {
            element.stringValue = sanitizeCSS(css)
        }
    }

    private static func sanitizeAttributes(on element: XMLElement) {
        for attribute in element.attributes ?? [] {
            guard let name = attribute.name?.lowercased() else {
                attribute.detach()
                continue
            }

            let value = attribute.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let lowercasedValue = value.lowercased()

            if name.hasPrefix("on") {
                attribute.detach()
                continue
            }

            if lowercasedValue.contains("javascript:") ||
                lowercasedValue.contains("vbscript:") {
                attribute.detach()
                continue
            }

            if name == "style" {
                if lowercasedValue.contains("@import") {
                    attribute.detach()
                    continue
                }

                attribute.stringValue = sanitizeCSS(value)
                continue
            }

            if urlReferenceAttributes.contains(name),
               !isSafeURLReference(value) {
                attribute.detach()
            }
        }
    }

    private static func sanitizeCSS(_ css: String) -> String {
        var sanitized = css.replacingOccurrences(
            of: "(?is)@import\\s+[^;]+;?",
            with: "",
            options: .regularExpression
        )

        sanitized = sanitized.replacingOccurrences(
            of: "(?i)javascript\\s*:",
            with: "",
            options: .regularExpression
        )

        sanitized = sanitized.replacingOccurrences(
            of: "(?i)vbscript\\s*:",
            with: "",
            options: .regularExpression
        )

        return sanitized
    }

    private static func isSafeURLReference(_ value: String) -> Bool {
        if value.isEmpty {
            return false
        }

        if value.hasPrefix("#") {
            return true
        }

        let lowercased = value.lowercased()
        if lowercased.hasPrefix("url(") {
            guard let open = value.firstIndex(of: "("),
                  let close = value.lastIndex(of: ")"),
                  open < close else {
                return false
            }

            let innerStart = value.index(after: open)
            var inner = String(value[innerStart..<close]).trimmingCharacters(in: .whitespacesAndNewlines)
            inner = inner.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return inner.hasPrefix("#")
        }

        return false
    }
}
