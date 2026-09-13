public import struct Foundation.UUID
public import UttrflowCore
public import UttrflowDictionary

/// One other spelling of a doubtful run, and the dictionary entry it came from when it came from one.
public struct Reading: Sendable, Hashable, ExpressibleByStringLiteral {
    /// The words as they would be written.
    public let spelling: String
    /// The entry that taught this spelling, so a reading the model takes is counted like a correction; `nil` off the screen or the vocabulary.
    public let entryID: UUID?

    public init(_ spelling: String, entryID: UUID? = nil) {
        self.spelling = spelling
        self.entryID = entryID
    }

    /// A reading nobody taught, which is what a literal in a test or a fixture is.
    public init(stringLiteral spelling: String) {
        self.init(spelling)
    }
}

/// Where another reading of a doubtful word can come from. See `Docs/cleanup-design.md` §5.
public protocol CandidateSource: Sendable {
    /// The readings this source offers for one run of doubtful words, best first, in single-digit milliseconds.
    func candidates(for word: Draft.Word, in situation: Situation) async -> [Reading]

    /// The readings for every run of one piece, so what a source derives from the screen is derived once.
    func candidates(for words: [Draft.Word], in situation: Situation) async -> [[Reading]]
}

extension CandidateSource {
    /// One run at a time, which is right for a source whose index does not depend on the situation.
    public func candidates(for words: [Draft.Word], in situation: Situation) async -> [[Reading]] {
        var found: [[Reading]] = []
        for word in words { found.append(await candidates(for: word, in: situation)) }
        return found
    }
}

/// A run of words the recogniser half-heard, and the readings the sources offered for it.
public struct DoubtfulSpan: Sendable, Equatable {
    /// The run as the model will read it, spaces and all, which is also what the guard looks for.
    public let heard: String
    /// The lowest confidence in the run, because a run is only as certain as its weakest word.
    public let confidence: Double
    /// The other readings, best first, each still carrying where it came from; a span with none is never offered to the model.
    public let candidates: [Reading]

    public init(heard: String, confidence: Double, candidates: [Reading]) {
        self.heard = heard
        self.confidence = confidence
        self.candidates = candidates
    }

    /// Lower-cased letters and digits, so "payment sheet" and `PaymentSheet` read as the same spelling.
    static func closedUp(_ text: String) -> String { ReadingRestraint.closedUp(text) }
}

/// Asks every source at once what the words the recogniser was unsure of could have been.
public struct DoubtfulWords: Sendable {
    /// The most spans one piece may offer, so a bad recognition cannot grow the prompt without bound.
    public static let maximumSpans = WordCorrectionEngine.maximumChangedInEvery
    /// The most readings one span may offer, so a crowded sound cannot spend the whole line.
    public static let maximumCandidatesPerSpan = 3

    /// Asked in this order, and their answers merged in it, so the user's own words come before the screen's.
    public let sources: [any CandidateSource]

    public init(sources: [any CandidateSource]) {
        self.sources = sources
    }

    /// The two sources that need nothing wired to them: the screen, and the words everybody knows.
    public static let standard = DoubtfulWords(sources: [ScreenCandidates(), PhoneticCandidates()])

    /// The standard sources with the user's own dictionary asked first.
    public static func including(
        dictionary index: @escaping @Sendable () async -> PhoneticIndex
    ) -> DoubtfulWords {
        DoubtfulWords(sources: [DictionaryCandidates(index: index)] + standard.sources)
    }

    /// Every doubtful run that a source had a reading for, most deserving first and never overlapping.
    public func spans(in draft: Draft, for situation: Situation) async -> [DoubtfulSpan] {
        // A draft whose confidences are a stand-in reads as certain throughout, so the feature must not fire.
        guard draft.confidencesAreReal, !sources.isEmpty else { return [] }
        let runs = UncertainSpan.spans(in: draft, below: WordCorrectionEngine.certaintyThreshold)
        guard !runs.isEmpty else { return [] }

        let offered = await readings(
            for: runs.map { Draft.Word(text: $0.text, heard: $0.text, confidence: $0.confidence) },
            in: situation)
        var found: [DoubtfulSpan] = []
        var taken: [Range<Int>] = []
        for (run, readings) in zip(runs, offered)
        where !readings.isEmpty && !taken.contains(where: { $0.overlaps(run.range) }) {
            taken.append(run.range)
            found.append(
                DoubtfulSpan(
                    heard: run.text, confidence: run.confidence,
                    candidates: Array(readings.prefix(Self.maximumCandidatesPerSpan))))
            if found.count == Self.maximumSpans { break }
        }
        return found
    }

    /// Every source's answer for every run, the sources running beside each other because they share nothing.
    private func readings(for words: [Draft.Word], in situation: Situation) async -> [[Reading]] {
        var answers: [[[Reading]]] = Array(repeating: [], count: sources.count)
        await withTaskGroup(of: (Int, [[Reading]]).self) { group in
            for (position, source) in sources.enumerated() {
                group.addTask { (position, await source.candidates(for: words, in: situation)) }
            }
            for await (position, found) in group { answers[position] = found }
        }
        return words.indices.map { index in Self.merged(answers.map { $0[index] }, heard: words[index].text) }
    }

    /// The sources' readings in the order they were asked, each once, and never the words as they were heard.
    static func merged(_ answers: [[Reading]], heard: String) -> [Reading] {
        var seen: Set<String> = []
        // The first to offer a spelling keeps it, which is the dictionary's, so a taught word keeps its entry.
        return answers.flatMap { $0 }
            .filter {
                $0.spelling != heard && !$0.spelling.isEmpty
                    && seen.insert($0.spelling.lowercased()).inserted
            }
    }
}
