import Testing
import UttrflowCore
import UttrflowDictionary

@testable import UttrflowAI

@Suite("Dictionary candidates: the user's own spellings")
struct DictionaryCandidatesTests {
    private let source = DictionaryCandidates(index: { CorrectionFixtures.index })

    /// The one source that knows which entry a spelling came from, so the count a taken reading earns reaches it.
    @Test("keeps the entry each spelling was taught by")
    func keepsTheEntry() async throws {
        let entry = try #require(CorrectionFixtures.entries.first { $0.word == "PaymentSheet" })

        let found = await source.candidates(
            for: Draft.Word("payment sheet", confidence: 0.3), in: .unknown)

        #expect(found.first { $0.spelling == "PaymentSheet" }?.entryID == entry.id)
    }

    @Test("offers the user's spelling for a run that sounds like it")
    func offersASpelling() async {
        let found = await source.candidates(
            for: Draft.Word("payment sheet", confidence: 0.3), in: .unknown)
        #expect(found.map(\.spelling).contains("PaymentSheet"))
    }

    @Test("offers nothing when the dictionary already spells the run exactly as it was heard")
    func offersNothingForItsOwnWord() async {
        let found = await source.candidates(for: Draft.Word("Claude", confidence: 0.3), in: .unknown)
        #expect(found.isEmpty)
    }

    @Test("offers nothing for a word no entry sounds like")
    func offersNothingForAStranger() async {
        let found = await source.candidates(for: Draft.Word("elephant", confidence: 0.3), in: .unknown)
        #expect(found.isEmpty)
    }

    @Test("answers the same question the correction engine asks of the same dictionary")
    func sharesTheEngineLookup() async {
        let found = await source.candidates(for: Draft.Word("kestral", confidence: 0.3), in: .unknown)
        let engine = WordCorrectionEngine.spellings(of: "kestral", in: CorrectionFixtures.index)
        #expect(
            found.map(\.spelling)
                == Array(engine.map(\.word).prefix(DictionaryCandidates.maximumOffered)))
        #expect(found.map(\.spelling).contains("Kestrel"))
    }

    @Test("offers at most two, so the screen and the ordinary words keep their places on the line")
    func capsWhatItOffers() async {
        let found = await source.candidates(for: Draft.Word("kestral", confidence: 0.3), in: .unknown)
        #expect(found.count <= DictionaryCandidates.maximumOffered)
    }
}
