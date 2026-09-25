import Foundation

enum SVGSanitizer {
    private static let blockedElements: Set<String> = [
        "script",
        "iframe",
        "object",
        "embed",
        "audio",
        "video",
        "img",
        "link",
        "meta",
        "base",
    ]

    private static let fragmentReferenceAttributes: Set<String> = [
        "href",
        "xlink:href",
    ]

    private static let localURLAttributes: Set<String> = [
        "clip-path",
        "filter",
        "mask",
        "marker-start",
        "marker-mid",
        "marker-end",
    ]

    private static let paintAttributes: Set<String> = [
        "fill",
        "stroke",
    ]

    private static let safeForeignObjectElements: Set<String> = [
        "div",
        "span",
        "p",
        "br",
        "strong",
        "em",
        "b",
        "i",
    ]

    static func sanitize(_ rawSVG: String) throws -> String {
        let data = Data(rawSVG.utf8)
        let document = try XMLDocument(data: data, options: [.nodePreserveAll])

        guard let root = document.rootElement(),
            root.name?.lowercased() == "svg"
        else {
            throw NSError(
                domain: "SVGSanitizer",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid SVG root element"]
            )
        }

        sanitizeElement(root, insideForeignObject: false)
        return document.xmlString(options: [.nodeCompactEmptyElement])
    }

    private static func sanitizeElement(_ element: XMLElement, insideForeignObject: Bool) {
        sanitizeAttributes(on: element)

        let parentName = normalizedName(element.name)
        let childrenAreForeignObjectContent = insideForeignObject || parentName == "foreignobject"

        for child in element.children ?? [] {
            guard let childElement = child as? XMLElement,
                let rawName = childElement.name
            else {
                continue
            }

            let elementName = normalizedName(rawName)
            if blockedElements.contains(elementName)
                || (childrenAreForeignObjectContent && !safeForeignObjectElements.contains(elementName))
            {
                child.detach()
                continue
            }

            sanitizeElement(childElement, insideForeignObject: childrenAreForeignObjectContent)
        }

        if element.name?.lowercased() == "style",
            let css = element.stringValue
        {
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

            if lowercasedValue.contains("javascript:") || lowercasedValue.contains("vbscript:") {
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

            if fragmentReferenceAttributes.contains(name),
                !isSafeFragmentReference(value)
            {
                attribute.detach()
                continue
            }

            if localURLAttributes.contains(name),
                !isSafeLocalURLValue(value)
            {
                attribute.detach()
                continue
            }

            if paintAttributes.contains(name),
                !hasOnlySafeURLFunctions(value)
            {
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

        sanitized = sanitized.replacingOccurrences(
            of: "(?i)url\\s*\\(\\s*(?![\"']?#)[^)]*\\)",
            with: "none",
            options: .regularExpression
        )

        return sanitized
    }

    private static func isSafeFragmentReference(_ value: String) -> Bool {
        if value.isEmpty {
            return false
        }

        return value.hasPrefix("#")
    }

    private static func isSafeLocalURLValue(_ value: String) -> Bool {
        let lowercased = value.lowercased()
        if lowercased == "none" {
            return true
        }

        if lowercased.range(of: "^url\\s*\\(", options: .regularExpression) != nil {
            return hasOnlySafeURLFunctions(value)
        }

        return false
    }

    private static func hasOnlySafeURLFunctions(_ value: String) -> Bool {
        let withoutSafeReferences = value.replacingOccurrences(
            of: "(?i)url\\s*\\(\\s*[\"']?#[^)'\"\\s]+[\"']?\\s*\\)",
            with: "",
            options: .regularExpression
        )
        return withoutSafeReferences.range(of: "(?i)url\\s*\\(", options: .regularExpression) == nil
    }

    private static func normalizedName(_ name: String?) -> String {
        name?.split(separator: ":").last?.lowercased() ?? ""
    }
}
