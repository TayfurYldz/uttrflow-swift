import Foundation
import Testing

@testable import UttrflowInput

@Suite("Backward selection over carets another app reports out of range")
struct BackwardSelectionHostileTests {
    /// Carets no field should report, each of which must read as unknown rather than trap.
    static let carets = [NSNotFound, .max, .max - 1, .min, -1, 6, 400]

    @Test("A caret outside the text is unreadable on every backward read.", arguments: carets)
    func caretsOutsideTheText(caret: Int) {
        for text in ["hello", ""] {
            #expect(BackwardSelection.range(in: text, endingAt: caret, covering: 1) == nil)
            #expect(BackwardSelection.text(in: text, endingAt: caret, exactly: 1) == nil)
            #expect(BackwardSelection.tail(in: text, endingAt: caret, upTo: 3) == nil)
            #expect(!BackwardSelection.confirms("o", in: text, endingAt: caret))
            #expect(BackwardSelection.replacing(in: text, location: caret, length: 1, covering: 1) == nil)
        }
    }

    @Test("A hostile count before the caret is refused or clamped, never trapped.")
    func hostileCounts() {
        #expect(BackwardSelection.range(in: "hello", endingAt: 5, covering: .max) == nil)
        #expect(BackwardSelection.range(in: "hello", endingAt: 5, covering: .min) == nil)
        #expect(BackwardSelection.text(in: "hello", endingAt: 5, exactly: -1) == nil)
        #expect(BackwardSelection.tail(in: "hello", endingAt: 5, upTo: .max) == "hello")
        #expect(BackwardSelection.tail(in: "hello", endingAt: 5, upTo: .min) == nil)
    }

    @Test("The replaced range runs from what is taken back to the selection's end, clamped to the text.")
    func replacingClampsTheSelection() {
        let table: [(location: Int, length: Int, range: Range<Int>?)] = [
            (3, 0, 1..<3), (3, 2, 1..<5), (3, 400, 1..<5), (3, .max, 1..<5), (3, -4, 1..<3),
            (3, .min, 1..<3), (5, .max, 3..<5), (1, 1, nil), (NSNotFound, 1, nil), (.min, .max, nil),
        ]
        for row in table {
            #expect(
                BackwardSelection.replacing(
                    in: "hello", location: row.location, length: row.length, covering: 2)
                    == row.range)
        }
        #expect(BackwardSelection.replacing(in: "", location: 0, length: .max, covering: 0) == 0..<0)
        #expect(BackwardSelection.replacing(in: "🐕a", location: 3, length: .max, covering: 1) == 2..<3)
    }
}
