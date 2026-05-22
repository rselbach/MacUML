import Foundation

extension NSRange {
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
}
