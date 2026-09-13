// The ordinary words that really are said the same way, which a sound key cannot tell from a collision.

/// Words pronounced alike, kept by hand because Double Metaphone files "main" with "man" as readily as "hear" with "here".
public enum Homophones {
    /// Whether two ordinary words are the same sound, which is what makes one a reading of the other.
    public static func share(_ word: String, _ other: String) -> Bool {
        let word = ReadingRestraint.closedUp(word)
        let other = ReadingRestraint.closedUp(other)
        guard word != other else { return false }
        return groups.contains { $0.contains(word) && $0.contains(other) }
    }

    /// Sets said identically; a pair whose vowels differ at all — "main" and "man" — belongs in none of them.
    static let groups: [Set<String>] = [
        ["allowed", "aloud"], ["bored", "board"], ["brake", "break"], ["capital", "capitol"],
        ["cell", "sell"], ["cent", "scent", "sent"], ["complement", "compliment"],
        ["die", "dye"], ["fair", "fare"], ["flew", "flu"], ["flour", "flower"],
        ["hear", "here"], ["hole", "whole"], ["knew", "new"], ["knight", "night"],
        ["mail", "male"], ["made", "maid"], ["meat", "meet"], ["need", "knead"],
        ["pain", "pane"], ["pair", "pear"], ["peace", "piece"], ["peak", "peek"],
        ["plain", "plane"], ["principal", "principle"], ["rain", "reign", "rein"],
        ["road", "rode"], ["role", "roll"], ["sail", "sale"], ["scene", "seen"],
        ["sea", "see"], ["son", "sun"], ["stationary", "stationery"], ["steal", "steel"],
        ["tail", "tale"], ["threw", "through"], ["toe", "tow"], ["vain", "vein"],
        ["waist", "waste"], ["wait", "weight"], ["way", "weigh"], ["weak", "week"],
        ["wood", "would"], ["write", "right", "rite"],
    ]
}
