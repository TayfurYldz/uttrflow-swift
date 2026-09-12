// Tests for reading a text as the amounts it states.

import Testing

@testable import UttrflowAI

@Suite("Reading amounts")
struct QuantityTests {
    @Test(
        "reads a number with the symbol attached to it",
        arguments: [
            ("revenue grew 5%", [Quantity(digits: "5", symbol: "%")]),
            ("the invoice is $500", [Quantity(digits: "500", symbol: "$")]),
            ("the gap is 20\u{00B0}", [Quantity(digits: "20", symbol: "\u{00B0}")]),
            ("i need 20 chairs", [Quantity(digits: "20", symbol: "")]),
            // One space is tolerated, since a model writing "5 %" means the percentage.
            ("revenue grew 5 %", [Quantity(digits: "5", symbol: "%")]),
        ]
    )
    func readsAnAmount(text: String, expected: [Quantity]) {
        #expect(Quantities.read(in: text) == expected)
    }

    /// The separator is a way of writing the number, not part of it, so both spellings are one amount.
    @Test("reads a thousands separator as part of the number")
    func readsASeparator() {
        #expect(Quantities.read(in: "we sold 12,000 units") == [Quantity(digits: "12000", symbol: "")])
        #expect(
            Quantities.read(in: "it cost $12,000") == [Quantity(digits: "12000", symbol: "$")])
    }

    @Test("reads every amount in the order the text states them")
    func readsEveryAmountInOrder() {
        #expect(
            Quantities.read(in: "5% of 20 rooms cost $300")
                == [
                    Quantity(digits: "5", symbol: "%"), Quantity(digits: "20", symbol: ""),
                    Quantity(digits: "300", symbol: "$"),
                ])
    }

    @Test("finds nothing in a text that states no number")
    func findsNothingInProse() {
        #expect(Quantities.read(in: "no numbers here at all").isEmpty)
    }

    @Test("names an amount the way it is written")
    func namesItAsWritten() {
        #expect(Quantity(digits: "5", symbol: "%").written == "5%")
        #expect(Quantity(digits: "500", symbol: "$").written == "$500")
        #expect(Quantity(digits: "20", symbol: "").written == "20")
    }
}

@Suite("The guard reads an amount, not a digit run")
struct QuantityGuardTests {
    @Test(
        "refuses a rewrite that dropped the symbol on a number",
        arguments: [
            ("revenue grew 5%", "Revenue grew 5."),
            ("the invoice is $500", "The invoice is 500."),
            ("the gap is 20\u{00B0}", "The gap is 20."),
            // Moved from one number to another, which the digit check cannot see either.
            ("5% of 20 rooms", "5 of 20% rooms."),
        ]
    )
    func refusesADroppedSymbol(kept: String, rewritten: String) {
        #expect(MeaningPreservationGuard.changedQuantity(original: kept, rewritten: rewritten) != nil)
    }

    @Test("refuses a symbol the rewrite attached to a number that had none")
    func refusesAnInventedSymbol() {
        #expect(
            MeaningPreservationGuard.changedQuantity(
                original: "i need 20 chairs", rewritten: "I need 20% chairs.") != nil)
    }

    @Test(
        "says nothing about a rewrite that kept every amount as it was",
        arguments: [
            ("revenue grew 5%", "Revenue grew 5%."),
            ("the invoice is $500", "The invoice is $500."),
            ("we sold 12,000 units", "We sold 12,000 units."),
            // The separator is a spelling, and the passes may write either.
            ("we sold 12,000 units", "We sold 12000 units."),
            ("i need 20 chairs", "I need 20 chairs."),
            ("no numbers here", "No numbers here."),
        ]
    )
    func acceptsAnAmountKept(kept: String, rewritten: String) {
        #expect(MeaningPreservationGuard.changedQuantity(original: kept, rewritten: rewritten) == nil)
    }
}
