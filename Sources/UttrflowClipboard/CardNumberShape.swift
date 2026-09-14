// Recognises a payment card number.

/// A card number: a network's prefix, a length it issues, and a Luhn pass. See Docs/clipboard-secrets.md.
enum CardNumberShape {
    /// Whether a card number stands anywhere in the text, on its own rather than inside a longer number.
    static func matches(_ text: String) -> Bool {
        CardNumberRuns.candidates(in: text, tally: SecretShapes.patternTally).contains { run in
            text[run].matches(of: candidate).contains { match in
                standsAlone(match.range, in: text) && isCardNumber(match.output.0.filter(\.isNumber))
            }
        }
    }

    /// Digits unbroken, or in printed groups with one separator throughout; `issuers` rules on length.
    nonisolated(unsafe) static let candidate =
        #/
        [0-9]{4}([\x20\-])[0-9]{4}\1[0-9]{4}\1[0-9]{4}(?:\1[0-9]{3})?   # 4-4-4-4 and 4-4-4-4-3
        | [0-9]{4}([\x20\-])[0-9]{6}\2[0-9]{4,5}                     # 4-6-5 and 4-6-4
        | [0-9]{4}([\x20\-])[0-9]{3}\3[0-9]{3}\3[0-9]{3}              # 4-3-3-3
        | [0-9]{13,19}
        /#

    /// What joins a number to more of itself in a date, a decimal, a time or an id; a space does not.
    private static let joiners: Set<Character> = ["-", ".", "/", ":", "_"]

    /// Whether the match is bounded by something other than more digits, directly or across one joiner.
    static func standsAlone(_ range: Range<String.Index>, in text: String) -> Bool {
        let before = text[..<range.lowerBound].suffix(2)
        let after = text[range.upperBound...].prefix(2)
        if let last = before.last {
            if last.isNumber || last == "+" { return false }
            if joiners.contains(last), before.count == 2, before.first?.isNumber == true { return false }
        }
        if let first = after.first {
            if first.isNumber { return false }
            if joiners.contains(first), after.count == 2, after.last?.isNumber == true { return false }
        }
        return true
    }

    /// Whether these digits are a length some network issues under its prefix, and pass Luhn.
    static func isCardNumber(_ digits: String) -> Bool {
        issued(digits) && luhn(digits)
    }

    /// Whether some network issues numbers of this length under this prefix.
    private static func issued(_ digits: String) -> Bool {
        issuers.contains { issuer in
            issuer.lengths.contains(digits.count)
                && Int(digits.prefix(issuer.width)).map(issuer.prefixes.contains) == true
        }
    }

    /// The networks in wide use; anything else is a number rather than a card.
    private static let issuers: [Issuer] = [
        Issuer(width: 1, prefixes: 4...4, lengths: [13, 16, 19]),  // Visa
        Issuer(width: 2, prefixes: 51...55, lengths: [16]),  // Mastercard
        Issuer(width: 4, prefixes: 2221...2720, lengths: [16]),  // Mastercard, 2-series
        Issuer(width: 2, prefixes: 34...34, lengths: [15]),  // American Express
        Issuer(width: 2, prefixes: 37...37, lengths: [15]),  // American Express
        Issuer(width: 2, prefixes: 36...36, lengths: [14, 16]),  // Diners Club
        Issuer(width: 3, prefixes: 300...305, lengths: [14, 16]),  // Diners Club
        Issuer(width: 4, prefixes: 3528...3589, lengths: Set(16...19)),  // JCB
        Issuer(width: 4, prefixes: 6011...6011, lengths: Set(16...19)),  // Discover
        Issuer(width: 3, prefixes: 644...649, lengths: Set(16...19)),  // Discover
        Issuer(width: 2, prefixes: 65...65, lengths: Set(16...19)),  // Discover, RuPay
        Issuer(width: 2, prefixes: 62...62, lengths: Set(16...19)),  // UnionPay
        Issuer(width: 2, prefixes: 60...60, lengths: [16]),  // RuPay
        Issuer(width: 2, prefixes: 81...82, lengths: [16]),  // RuPay
        Issuer(width: 3, prefixes: 508...508, lengths: [16]),  // RuPay
        Issuer(width: 4, prefixes: 2200...2204, lengths: Set(16...19)),  // Mir
        Issuer(width: 4, prefixes: 5018...5018, lengths: Set(13...19)),  // Maestro
        Issuer(width: 4, prefixes: 5020...5020, lengths: Set(13...19)),  // Maestro
        Issuer(width: 4, prefixes: 5038...5038, lengths: Set(13...19)),  // Maestro
        Issuer(width: 4, prefixes: 5893...5893, lengths: Set(13...19)),  // Maestro
        Issuer(width: 4, prefixes: 6304...6304, lengths: Set(13...19)),  // Maestro
        Issuer(width: 4, prefixes: 6759...6763, lengths: Set(13...19)),  // Maestro
    ]

    /// The Luhn checksum every card network uses, which a mistyped digit fails.
    private static func luhn(_ digits: String) -> Bool {
        let sum = digits.reversed().enumerated().reduce(0) { total, next in
            guard let digit = next.element.wholeNumberValue else { return total }
            let weighed = next.offset.isMultiple(of: 2) ? digit : digit * 2
            return total + (weighed > 9 ? weighed - 9 : weighed)
        }
        return sum.isMultiple(of: 10)
    }
}

/// A network's prefixes, read over its leading `width` digits, and the lengths it issues under them.
private struct Issuer {
    let width: Int
    let prefixes: ClosedRange<Int>
    let lengths: Set<Int>
}
