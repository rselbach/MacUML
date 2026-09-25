import Foundation

enum SVGSanitizer {
    private static let blockedElements: Set<String> = [
        "animate",
        "animatecolor",
        "animatemotion",
        "animatetransform",
        "discard",
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
        "set",
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

    private static let resourceAttributes: Set<String> = [
        "background",
        "base",
        "cursor",
        "data",
        "poster",
        "src",
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

    private static let allowedCSSProperties: Set<String> = [
        "alignment-baseline", "align-items", "align-self", "background-color",
        "border", "border-bottom", "border-bottom-color", "border-bottom-left-radius",
        "border-bottom-right-radius", "border-bottom-style", "border-bottom-width", "border-color",
        "border-left", "border-left-color", "border-left-style", "border-left-width", "border-radius",
        "border-right", "border-right-color", "border-right-style", "border-right-width", "border-style",
        "border-top", "border-top-color", "border-top-left-radius", "border-top-right-radius",
        "border-top-style", "border-top-width", "border-width", "box-sizing", "clip-path", "color",
        "direction", "display", "dominant-baseline", "fill", "fill-opacity", "fill-rule", "filter", "flex",
        "flex-basis", "flex-direction", "flex-grow", "flex-shrink", "flex-wrap", "font", "font-family",
        "font-size", "font-stretch", "font-style", "font-variant", "font-weight", "gap", "height",
        "justify-content", "letter-spacing", "line-height", "margin", "margin-bottom", "margin-left",
        "margin-right", "margin-top", "marker", "marker-end", "marker-mid", "marker-start", "mask",
        "max-height", "max-width", "min-height", "min-width", "opacity", "overflow", "overflow-wrap",
        "padding", "padding-bottom", "padding-left", "padding-right", "padding-top", "paint-order",
        "pointer-events", "position", "rx", "ry", "shape-rendering", "stop-color", "stop-opacity", "stroke",
        "stroke-dasharray", "stroke-dashoffset", "stroke-linecap", "stroke-linejoin", "stroke-miterlimit",
        "stroke-opacity", "stroke-width", "text-align", "text-anchor", "text-decoration", "text-overflow",
        "text-rendering", "transform", "transform-origin", "unicode-bidi", "vertical-align", "visibility",
        "white-space", "width", "word-break", "word-spacing", "word-wrap",
    ]

    private static let allowedCSSFunctions: Set<String> = [
        "blur", "brightness", "calc", "clamp", "color", "contrast", "drop-shadow", "grayscale", "hsl", "hsla",
        "hue-rotate", "hwb", "invert", "lab", "lch", "matrix", "matrix3d", "max", "min", "oklab", "oklch",
        "opacity", "perspective", "rgb", "rgba", "rotate", "rotate3d", "rotatex", "rotatey", "rotatez",
        "saturate", "scale", "scale3d", "scalex", "scaley", "sepia", "skew", "skewx", "skewy", "translate",
        "translate3d", "translatex", "translatey",
    ]

    static func sanitize(_ rawSVG: String) throws -> String {
        let data = Data(rawSVG.utf8)
        let document = try XMLDocument(data: data, options: [.nodePreserveAll, .nodeLoadExternalEntitiesNever])

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
        return root.xmlString(options: [.nodeCompactEmptyElement])
    }

    private static func sanitizeElement(_ element: XMLElement, insideForeignObject: Bool) {
        sanitizeAttributes(on: element)

        let parentName = normalizedName(element.name)
        let childrenAreForeignObjectContent = insideForeignObject || parentName == "foreignobject"

        for child in element.children ?? [] {
            guard let childElement = child as? XMLElement,
                let rawName = childElement.name
            else {
                if child.kind == .processingInstruction {
                    child.detach()
                }
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

        if parentName == "style", let css = element.stringValue {
            let sanitized = sanitizeStylesheet(css)
            if sanitized.isEmpty {
                element.detach()
            } else {
                element.stringValue = sanitized
            }
        }
    }

    private static func sanitizeAttributes(on element: XMLElement) {
        for attribute in element.attributes ?? [] {
            guard let name = attribute.name?.lowercased() else {
                attribute.detach()
                continue
            }
            let localName = normalizedName(name)

            let value = attribute.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if localName.hasPrefix("on") || resourceAttributes.contains(localName) {
                attribute.detach()
                continue
            }

            if localName == "style" {
                let sanitized = sanitizeDeclarations(value)
                if sanitized.isEmpty {
                    attribute.detach()
                } else {
                    attribute.stringValue = sanitized
                }
                continue
            }

            if fragmentReferenceAttributes.contains(name) || localName == "href" {
                if !isSafeFragmentReference(value) {
                    attribute.detach()
                }
                continue
            }

            if localURLAttributes.contains(localName) {
                if !isSafeLocalURLValue(value) {
                    attribute.detach()
                }
                continue
            }

            if paintAttributes.contains(localName) {
                if !isSafeCSSValue(value, property: localName) {
                    attribute.detach()
                }
                continue
            }

            if containsResourceFunction(value) {
                attribute.detach()
            }
        }
    }

    private static func sanitizeStylesheet(_ css: String) -> String {
        guard let canonical = canonicalCSS(css) else { return "" }

        return stylesheetRules(in: canonical).compactMap { selector, body in
            let trimmedSelector = selector.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedSelector.isEmpty, !trimmedSelector.hasPrefix("@") else { return nil }
            let declarations = sanitizeDeclarations(body)
            guard !declarations.isEmpty else { return nil }
            return "\(trimmedSelector){\(declarations)}"
        }.joined()
    }

    private static func sanitizeDeclarations(_ declarations: String) -> String {
        guard let canonical = canonicalCSS(declarations) else { return "" }

        return splitCSS(canonical, at: ";").compactMap { declaration in
            guard let colon = firstCSSSeparator(":", in: declaration) else { return nil }
            let property = declaration[..<colon].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let valueStart = declaration.index(after: colon)
            let value = declaration[valueStart...].trimmingCharacters(in: .whitespacesAndNewlines)
            guard allowedCSSProperties.contains(property), isSafeCSSValue(value, property: property) else {
                return nil
            }
            return "\(property):\(value)"
        }.joined(separator: ";")
    }

    private static func isSafeCSSValue(_ rawValue: String, property: String) -> Bool {
        guard let value = canonicalCSS(rawValue), !value.isEmpty,
            !value.contains("{"), !value.contains("}"), !value.contains(";"), !value.contains("@")
        else {
            return false
        }

        guard let functions = cssFunctions(in: value) else { return false }
        for function in functions {
            if function.name == "url" {
                guard localURLAttributes.contains(property) || paintAttributes.contains(property),
                    isSafeFragmentReference(unquoted(function.argument))
                else {
                    return false
                }
            } else if !allowedCSSFunctions.contains(function.name) {
                return false
            }
        }
        return true
    }

    private static func containsResourceFunction(_ value: String) -> Bool {
        guard let canonical = canonicalCSS(value), let functions = cssFunctions(in: canonical) else {
            return true
        }
        return functions.contains {
            $0.name == "url" || $0.name == "image-set" || $0.name == "-webkit-image-set"
        }
    }

    private static func isSafeFragmentReference(_ value: String) -> Bool {
        let fragment = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard fragment.first == "#", fragment.count > 1 else { return false }
        return fragment.dropFirst().allSatisfy {
            $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "." || $0 == ":"
        }
    }

    private static func isSafeLocalURLValue(_ value: String) -> Bool {
        if value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "none" {
            return true
        }
        return isSafeCSSValue(value, property: "filter")
    }

    private static func stylesheetRules(in css: String) -> [(selector: String, body: String)] {
        let scalars = Array(css.unicodeScalars)
        var rules: [(selector: String, body: String)] = []
        var selectorStart = 0
        var bodyStart: Int?
        var depth = 0
        var quote: Unicode.Scalar?
        var nested = false

        for (index, scalar) in scalars.enumerated() {
            if let activeQuote = quote {
                if scalar == activeQuote { quote = nil }
                continue
            }
            if scalar == "\"" || scalar == "'" {
                quote = scalar
            } else if scalar == "{" {
                depth += 1
                if depth == 1 {
                    bodyStart = index + 1
                } else {
                    nested = true
                }
            } else if scalar == "}" {
                guard depth > 0 else {
                    selectorStart = index + 1
                    continue
                }
                depth -= 1
                if depth == 0, let start = bodyStart {
                    if !nested {
                        let selector = String(String.UnicodeScalarView(scalars[selectorStart..<(start - 1)]))
                        let body = String(String.UnicodeScalarView(scalars[start..<index]))
                        rules.append((selector, body))
                    }
                    selectorStart = index + 1
                    bodyStart = nil
                    nested = false
                }
            }
        }

        guard depth == 0, quote == nil else { return [] }
        return rules
    }

    private static func cssFunctions(in value: String) -> [(name: String, argument: String)]? {
        let scalars = Array(value.unicodeScalars)
        var functions: [(name: String, argument: String)] = []
        var stack: [(name: String, argumentStart: Int)] = []
        var quote: Unicode.Scalar?

        for (index, scalar) in scalars.enumerated() {
            if let activeQuote = quote {
                if scalar == activeQuote { quote = nil }
                continue
            }
            if scalar == "\"" || scalar == "'" {
                quote = scalar
            } else if scalar == "(" {
                var nameEnd = index
                var nameStart = nameEnd
                while nameStart > 0, CharacterSet.whitespacesAndNewlines.contains(scalars[nameStart - 1]) {
                    nameStart -= 1
                }
                nameEnd = nameStart
                while nameStart > 0, isCSSIdentifierScalar(scalars[nameStart - 1]) {
                    nameStart -= 1
                }
                guard nameStart < nameEnd else { return nil }
                let name = String(String.UnicodeScalarView(scalars[nameStart..<nameEnd])).lowercased()
                stack.append((name, index + 1))
            } else if scalar == ")" {
                guard let function = stack.popLast() else { return nil }
                let argument = String(String.UnicodeScalarView(scalars[function.argumentStart..<index]))
                functions.append((function.name, argument))
            }
        }

        guard quote == nil, stack.isEmpty else { return nil }
        return functions
    }

    private static func splitCSS(_ value: String, at separator: Unicode.Scalar) -> [String] {
        let scalars = Array(value.unicodeScalars)
        var components: [String] = []
        var start = 0
        var depth = 0
        var quote: Unicode.Scalar?

        for (index, scalar) in scalars.enumerated() {
            if let activeQuote = quote {
                if scalar == activeQuote { quote = nil }
                continue
            }
            if scalar == "\"" || scalar == "'" {
                quote = scalar
            } else if scalar == "(" {
                depth += 1
            } else if scalar == ")" {
                depth = max(0, depth - 1)
            } else if scalar == separator, depth == 0 {
                components.append(String(String.UnicodeScalarView(scalars[start..<index])))
                start = index + 1
            }
        }
        components.append(String(String.UnicodeScalarView(scalars[start...])))
        return components
    }

    private static func firstCSSSeparator(_ separator: Character, in value: String) -> String.Index? {
        var depth = 0
        var quote: Character?
        for index in value.indices {
            let character = value[index]
            if let activeQuote = quote {
                if character == activeQuote { quote = nil }
                continue
            }
            if character == "\"" || character == "'" {
                quote = character
            } else if character == "(" {
                depth += 1
            } else if character == ")" {
                depth = max(0, depth - 1)
            } else if character == separator, depth == 0 {
                return index
            }
        }
        return nil
    }

    private static func canonicalCSS(_ css: String) -> String? {
        let scalars = Array(css.unicodeScalars)
        var withoutComments = String.UnicodeScalarView()
        var index = 0

        while index < scalars.count {
            if scalars[index] == "/", index + 1 < scalars.count, scalars[index + 1] == "*" {
                index += 2
                var foundEnd = false
                while index + 1 < scalars.count {
                    if scalars[index] == "*", scalars[index + 1] == "/" {
                        index += 2
                        foundEnd = true
                        break
                    }
                    index += 1
                }
                guard foundEnd else { return nil }
            } else {
                withoutComments.append(scalars[index])
                index += 1
            }
        }

        return decodeCSSEscapes(String(withoutComments))
    }

    private static func decodeCSSEscapes(_ value: String) -> String {
        let scalars = Array(value.unicodeScalars)
        var decoded = String.UnicodeScalarView()
        var index = 0

        while index < scalars.count {
            guard scalars[index] == "\\" else {
                decoded.append(scalars[index])
                index += 1
                continue
            }

            index += 1
            guard index < scalars.count else { break }
            if scalars[index] == "\n" || scalars[index] == "\r" || scalars[index] == "\u{000C}" {
                if scalars[index] == "\r", index + 1 < scalars.count, scalars[index + 1] == "\n" {
                    index += 1
                }
                index += 1
                continue
            }

            var codePoint: UInt32 = 0
            var digitCount = 0
            while index < scalars.count, digitCount < 6, let digit = hexValue(scalars[index]) {
                codePoint = (codePoint * 16) + digit
                digitCount += 1
                index += 1
            }
            if digitCount > 0 {
                decoded.append(Unicode.Scalar(codePoint) ?? "\u{FFFD}")
                if index < scalars.count, CharacterSet.whitespacesAndNewlines.contains(scalars[index]) {
                    index += 1
                }
                continue
            }

            decoded.append(scalars[index])
            index += 1
        }

        return String(decoded)
    }

    private static func unquoted(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2, let first = trimmed.first, let last = trimmed.last,
            (first == "\"" && last == "\"") || (first == "'" && last == "'")
        else {
            return trimmed
        }
        return String(trimmed.dropFirst().dropLast())
    }

    private static func isCSSIdentifierScalar(_ scalar: Unicode.Scalar) -> Bool {
        CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_"
    }

    private static func hexValue(_ scalar: Unicode.Scalar) -> UInt32? {
        switch scalar.value {
        case 48...57: scalar.value - 48
        case 65...70: scalar.value - 55
        case 97...102: scalar.value - 87
        default: nil
        }
    }

    private static func normalizedName(_ name: String?) -> String {
        name?.split(separator: ":").last?.lowercased() ?? ""
    }
}
