import Foundation

extension NSRange {
    /// Returns a safe range clamped to the given maximum length.
    /// Returns nil if the range is invalid or outside bounds.
    func clamped(to maxLength: Int) -> NSRange? {
        guard maxLength > 0,
              location != NSNotFound,
              location < maxLength else {
            return nil
        }
        let documentRange = NSRange(location: 0, length: maxLength)
        let result = NSIntersectionRange(self, documentRange)
        guard result.length > 0 else { return nil }
        return result
    }

    /// Returns a non-nil safe range clamped to the given maximum length.
    /// Returns a zero-length range at location 0 if the range is invalid.
    func safeClamped(to maxLength: Int) -> NSRange {
        guard location != NSNotFound, location < maxLength else {
            return NSRange(location: 0, length: 0)
        }
        let safeLength = min(length, max(0, maxLength - location))
        return NSRange(location: location, length: safeLength)
    }
}
