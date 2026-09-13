import Foundation

/// Reads a range another app reports through Accessibility, which may hold any value at all.
enum AccessibilityRange {
    /// Where the selection ends, or `nil` when the location is `NSNotFound` or the end is past `Int.max`; a negative length is empty.
    static func end(location: Int, length: Int) -> Int? {
        guard location != NSNotFound else { return nil }
        let (end, overflow) = location.addingReportingOverflow(max(length, 0))
        return overflow ? nil : end
    }

    /// The selection as UTF-16 offsets, or `nil` when it has no end; the reader still clamps it into the text.
    static func selection(location: Int, length: Int) -> Range<Int>? {
        end(location: location, length: length).map { location..<$0 }
    }

    /// An empty range widened to the character before it, which a style read needs, without stepping below zero.
    static func widenedForStyle(_ range: CFRange) -> CFRange {
        range.length > 0 ? range : CFRange(location: max(range.location, 1) - 1, length: 1)
    }
}
