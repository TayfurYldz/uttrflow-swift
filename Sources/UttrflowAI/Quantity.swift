// A number as written, with whatever symbol is attached to it.

/// A number and the symbol it carries, since "5%" and "5" are different amounts and share a digit run.
struct Quantity: Equatable, Hashable {
    /// The digits, with thousands separators already taken out so 12,000 and 12000 are one number.
    let digits: String
    /// A currency before the digits or a percent or degree after them; empty for a bare number.
    let symbol: String

    /// How it reads, for a refusal that has to name what went missing.
    var written: String { symbol == "%" || symbol == "\u{00B0}" ? digits + symbol : symbol + digits }
}

/// Reading the quantities out of a text, which is a different job from splitting it into words.
enum Quantities {
    /// Symbols that stand before the digits they belong to.
    static let leading: Set<Character> = ["$", "\u{00A3}", "\u{20AC}", "\u{20B9}", "\u{00A5}"]

    /// Symbols that stand after the digits they belong to.
    static let trailing: Set<Character> = ["%", "\u{00B0}"]

    /// Every number the text states, in order, each with the symbol attached to it.
    static func read(in text: String) -> [Quantity] {
        let characters = Array(text)
        var found: [Quantity] = []
        var index = 0
        while index < characters.count {
            guard characters[index].isNumber else {
                index += 1
                continue
            }
            var end = index
            while end < characters.count, characters[end].isNumber || isSeparator(characters, at: end) {
                end += 1
            }
            let digits = String(characters[index..<end]).filter(\.isNumber)
            found.append(Quantity(digits: digits, symbol: symbol(around: characters, from: index, to: end)))
            index = end
        }
        return found
    }

    /// Whether the character at `index` is a separator inside a number rather than the end of it.
    private static func isSeparator(_ characters: [Character], at index: Int) -> Bool {
        guard characters[index] == ",", index + 1 < characters.count else { return false }
        return characters[index + 1].isNumber
    }

    /// The symbol this run of digits carries: one before it, or one after it with at most a space between.
    private static func symbol(around characters: [Character], from start: Int, to end: Int) -> String {
        if start > 0, leading.contains(characters[start - 1]) { return String(characters[start - 1]) }
        var after = end
        if after < characters.count, characters[after] == " " { after += 1 }
        if after < characters.count, trailing.contains(characters[after]) {
            return String(characters[after])
        }
        return ""
    }
}
