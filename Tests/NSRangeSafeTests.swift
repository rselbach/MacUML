import Testing
import Foundation
@testable import MacUML

@Suite("NSRange Safe Extension Tests")
struct NSRangeSafeTests {
    @Test("Valid range within bounds returns same range")
    func validRangeWithinBounds() {
        let range = NSRange(location: 5, length: 10)
        let result = range.clamped(to: 100)

        #expect(result == NSRange(location: 5, length: 10))
    }

    @Test("Range at start of document")
    func rangeAtStart() {
        let range = NSRange(location: 0, length: 5)
        let result = range.clamped(to: 100)

        #expect(result == NSRange(location: 0, length: 5))
    }

    @Test("Range extending beyond max is clamped")
    func rangeBeyondMaxClamped() {
        let range = NSRange(location: 90, length: 20) // Would go to 110
        let result = range.clamped(to: 100)

        #expect(result == NSRange(location: 90, length: 10))
    }

    @Test("Range starting at max length returns nil")
    func rangeStartingAtMaxLength() {
        let range = NSRange(location: 100, length: 5)
        let result = range.clamped(to: 100)

        #expect(result == nil)
    }

    @Test("Range completely outside bounds returns nil")
    func rangeOutsideBounds() {
        let range = NSRange(location: 200, length: 10)
        let result = range.clamped(to: 100)

        #expect(result == nil)
    }

    @Test("NSNotFound location returns nil")
    func notFoundLocation() {
        let range = NSRange(location: NSNotFound, length: 10)
        let result = range.clamped(to: 100)

        #expect(result == nil)
    }

    @Test("Zero maxLength returns nil")
    func zeroMaxLength() {
        let range = NSRange(location: 0, length: 5)
        let result = range.clamped(to: 0)

        #expect(result == nil)
    }

    @Test("Zero length range within bounds returns nil")
    func zeroLengthRange() {
        let range = NSRange(location: 10, length: 0)
        let result = range.clamped(to: 100)

        // Zero length ranges are filtered out
        #expect(result == nil)
    }

    @Test("Range partially overlapping start")
    func rangePartiallyOverlappingStart() {
        // This is actually impossible with NSIntersectionRange since location can't be negative
        // But let's test the intersection behavior
        let range = NSRange(location: 0, length: 50)
        let result = range.clamped(to: 30)

        #expect(result == NSRange(location: 0, length: 30))
    }
}
