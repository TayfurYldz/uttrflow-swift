// The dictionary arranged by sound.

private import struct Foundation.UUID
package import UttrflowCore

/// The dictionary arranged by sound, so a lookup costs the same with fifty thousand entries as with ten.
public struct PhoneticIndex: Sendable, Equatable {
    /// The most entries kept for any one sound, which is what makes a lookup constant-time.
    public static let maximumPerSound = 8

    /// How many candidates one utterance may produce: a ceiling on the shortlist, not on the dictionary.
    public static let defaultCandidateLimit = 24

    /// The longest run of spoken words that can be one entry; `setUserPrefs` is said as three.
    public static let maximumWordsPerEntry = 3

    /// Counts every entry a lookup reads, so a test can show the cost does not follow the dictionary's size.
    @TaskLocal package static var entriesRead: WorkTally?

    private let buckets: Buckets

    /// Entries no coder could address, which nothing can ever look up; empty unless a spelling is all punctuation.
    public let unaddressable: [DictionaryEntry]

    /// Files every trustworthy entry under every sound it could be heard as, and names any it could not file.
    public init(entries: [DictionaryEntry]) {
        var buckets: [String: [DictionaryEntry]] = [:]
        var unfiled: [DictionaryEntry] = []
        for entry in entries where entry.isTrustworthy {
            let keys = PronunciationCoder.keys(for: entry.soundsLike)
            guard !keys.isEmpty else {
                unfiled.append(entry)
                continue
            }
            for key in keys {
                buckets[key, default: []].append(entry)
            }
        }
        self.unaddressable = unfiled
        self.buckets = Buckets(
            buckets.mapValues {
                Array($0.sorted(by: PhoneticIndex.isMoreUseful).prefix(PhoneticIndex.maximumPerSound))
            })
    }

    /// Everything that could be what the speaker said: one hash probe per code, then a bounded bucket.
    public func candidates(soundingLike word: String) -> [DictionaryEntry] {
        var seen: Set<UUID> = []
        var found: [DictionaryEntry] = []
        for key in PronunciationCoder.keys(for: word) {
            for entry in buckets[key] where seen.insert(entry.id).inserted {
                found.append(entry)
            }
        }
        return found
    }

    /// The guarantee: the candidates for one utterance, a function of the utterance and the limit alone.
    public func candidates(
        for utterance: Utterance, limit: Int = PhoneticIndex.defaultCandidateLimit
    ) -> [DictionaryEntry] {
        guard limit > 0 else { return [] }
        var seen: Set<UUID> = []
        var found: [DictionaryEntry] = []
        for span in utterance.spans(upTo: PhoneticIndex.maximumWordsPerEntry) {
            for entry in candidates(soundingLike: span.text) where seen.insert(entry.id).inserted {
                found.append(entry)
                if found.count == limit { return found }
            }
        }
        return found
    }

    /// Which of two entries sharing a sound deserves the bucket slot; a total order, down to the identifier.
    static func isMoreUseful(_ first: DictionaryEntry, _ second: DictionaryEntry) -> Bool {
        // Uses the user did not undo, so a constantly reverted word does not outrank one that works.
        let firstNet = first.timesUsed - first.timesReverted
        let secondNet = second.timesUsed - second.timesReverted
        if firstNet != secondNet { return firstNet > secondNet }
        if first.firstSeen != second.firstSeen { return first.firstSeen > second.firstSeen }
        if first.word != second.word { return first.word < second.word }
        return first.id.uuidString < second.id.uuidString
    }
}

extension PhoneticIndex {
    /// The entries filed by sound, reachable only through accessors that count what they hand out.
    private struct Buckets: Sendable, Equatable, Sequence {
        private let storage: [String: [DictionaryEntry]]

        init(_ storage: [String: [DictionaryEntry]]) {
            self.storage = storage
        }

        /// The entries filed under one sound, counted as read.
        subscript(key: String) -> [DictionaryEntry] {
            let bucket = storage[key] ?? []
            PhoneticIndex.entriesRead?.record(bucket.count)
            return bucket
        }

        /// Every bucket in turn, each counted as read when it is reached.
        func makeIterator()
            -> LazyMapSequence<[String: [DictionaryEntry]], (key: String, entries: [DictionaryEntry])>
            .Iterator
        {
            storage.lazy.map { key, entries in
                PhoneticIndex.entriesRead?.record(entries.count)
                return (key, entries)
            }.makeIterator()
        }
    }
}
