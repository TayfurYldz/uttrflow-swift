import CoreFoundation
import Foundation
import Testing

@testable import UttrflowContext

/// A selection another app might report, however broken, and what reading it should give.
struct HostileSelection: Sendable, CustomTestStringConvertible {
    let name: String
    let value: String
    let location: Int
    let length: Int

    var testDescription: String { name }

    var snapshot: FocusedFieldSnapshot {
        FocusedFieldSnapshot(
            bundleIdentifier: "com.example.editor", applicationName: "Example", role: "AXTextArea",
            value: value, selection: NSRange(location: location, length: length))
    }
}

private let hostile: [HostileSelection] = [
    .init(name: "NSNotFound with a length", value: "hello", location: NSNotFound, length: 1),
    .init(name: "NSNotFound, empty", value: "hello", location: NSNotFound, length: 0),
    .init(name: "Int.max with Int.max", value: "hello", location: .max, length: .max),
    .init(name: "just below Int.max with a length", value: "hello", location: .max - 1, length: 2),
    .init(name: "Int.min with a negative length", value: "hello", location: .min, length: -1),
    .init(name: "Int.min, empty", value: "hello", location: .min, length: 0),
    .init(name: "negative location", value: "hello", location: -3, length: 1),
    .init(name: "negative length", value: "hello", location: 2, length: -5),
    .init(name: "location past the text", value: "hello", location: 40, length: 0),
    .init(name: "length past the text", value: "hello", location: 1, length: 400),
    .init(name: "length of Int.max", value: "hello", location: 1, length: .max),
    .init(name: "empty text at NSNotFound", value: "", location: NSNotFound, length: 3),
    .init(name: "empty text past its end", value: "", location: 7, length: 7),
    .init(name: "multi-line text at NSNotFound", value: "one\ntwo", location: NSNotFound, length: 1),
]

@Suite("Selections another app reports out of range")
struct HostileSelectionTests {
    @Test("A selection at NSNotFound with a length reads as a caret not at the line's end, without trapping.")
    func reportedRepro() {
        let snapshot = FocusedFieldSnapshot(
            bundleIdentifier: "com.example.editor", applicationName: "Example", role: "AXTextArea",
            value: "hello", selection: NSRange(location: NSNotFound, length: 1))
        #expect(!snapshot.caretAtLineEnd)
    }

    @Test("Every reading of a snapshot survives a hostile selection.", arguments: hostile)
    func snapshotReadsSurvive(selection: HostileSelection) {
        let snapshot = selection.snapshot
        if AccessibilityRange.end(location: selection.location, length: selection.length) == nil {
            #expect(!snapshot.caretAtLineEnd)
        }
        #expect(snapshot.currentLine.isEmpty || selection.value.contains(snapshot.currentLine))
        _ = snapshot.preceding(maxLength: 40)
        #expect(snapshot.hasSelection == (selection.length > 0))
    }

    @Test(
        "The side texts of a hostile selection are either unknown or cut from the value.", arguments: hostile)
    func caretTextSurvives(selection: HostileSelection) {
        let range = AccessibilityRange.selection(location: selection.location, length: selection.length)
        let sides = CaretText.around(selection.value, selection: range)
        #expect((sides == nil) == (range == nil))
        guard let sides else { return }
        #expect(selection.value.hasPrefix(sides.preceding))
        #expect(selection.value.hasSuffix(sides.following))
    }

    @Test("The end of a selection is unknown exactly at NSNotFound or past Int.max.")
    func ends() {
        let table: [(location: Int, length: Int, end: Int?)] = [
            (NSNotFound, 1, nil), (NSNotFound, 0, nil), (.max - 1, 2, nil), (1, .max, nil),
            (.max - 1, 1, .max), (.min, -1, .min), (.min, .max, -1), (-3, 1, -2), (2, -5, 2),
            (40, 0, 40), (1, 400, 401), (0, 0, 0), (3, 2, 5),
        ]
        for row in table {
            #expect(AccessibilityRange.end(location: row.location, length: row.length) == row.end)
        }
    }

    @Test("A selection's range starts at its location and is empty for a negative length.")
    func selections() {
        #expect(AccessibilityRange.selection(location: 2, length: 3) == 2..<5)
        #expect(AccessibilityRange.selection(location: 2, length: -5) == 2..<2)
        #expect(AccessibilityRange.selection(location: -3, length: 1) == -3..<(-2))
        #expect(AccessibilityRange.selection(location: NSNotFound, length: 1) == nil)
        #expect(AccessibilityRange.selection(location: 1, length: .max) == nil)
    }

    @Test("Widening an empty range for a style read never steps below zero.")
    func widening() {
        let table: [(CFRange, CFRange)] = [
            (CFRange(location: 5, length: 0), CFRange(location: 4, length: 1)),
            (CFRange(location: 0, length: 0), CFRange(location: 0, length: 1)),
            (CFRange(location: .min, length: 0), CFRange(location: 0, length: 1)),
            (CFRange(location: -4, length: -2), CFRange(location: 0, length: 1)),
            (CFRange(location: NSNotFound, length: 0), CFRange(location: NSNotFound - 1, length: 1)),
            (CFRange(location: NSNotFound, length: 3), CFRange(location: NSNotFound, length: 3)),
            (CFRange(location: 2, length: 3), CFRange(location: 2, length: 3)),
        ]
        for (range, widened) in table {
            let answer = AccessibilityRange.widenedForStyle(range)
            #expect(answer.location == widened.location && answer.length == widened.length)
        }
    }
}
