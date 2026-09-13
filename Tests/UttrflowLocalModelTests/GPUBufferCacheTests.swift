import os
import Testing
import UttrflowPredict

@testable import UttrflowLocalModel

/// Counts what a scorer asks of the buffer cache, in the order it asks.
private final class CacheRecorder: Sendable {
    private let calls = OSAllocatedUnfairLock<[String]>(initialState: [])

    var recorded: [String] { calls.withLock { $0 } }

    var control: BufferCacheControl {
        BufferCacheControl(
            hold: { self.calls.withLock { $0.append("hold") } },
            clear: { self.calls.withLock { $0.append("clear") } })
    }
}

@Suite("The GPU buffer cache around a pass")
struct GPUBufferCacheTests {
    private let situation = GenerationSituation(application: "Mail", surroundings: "the draft looks fine")

    @Test("A generation pass caps the cache before it runs and empties it after")
    func generationHoldsThenClears() async throws {
        let recorder = CacheRecorder()
        let scorer = MLXCandidateScorer(model: .gemma3, maximumTokens: 16, bufferCache: recorder.control)
        for typed in ["Thanks for sending", "Could we move the review to ", "Sounds good, let"] {
            _ = try await scorer.completions(for: typed, in: situation)
        }
        #expect(recorder.recorded == Array(repeating: ["hold", "clear"], count: 3).flatMap { $0 })
    }

    @Test("Every other way into the model does the same")
    func everyEntryHoldsThenClears() async throws {
        let recorder = CacheRecorder()
        let scorer = MLXCandidateScorer(model: .gemma3, maximumTokens: 16, bufferCache: recorder.control)
        _ = try await scorer.pass(for: "git che", in: situation)
        _ = try await scorer.alternatives(for: "git che", in: situation, excluding: "git checkout")
        _ = await scorer.judgedTokens(of: "git checkout main", following: "git che")
        _ = await scorer.logLikelihood(of: "git checkout main", following: "git che")
        #expect(recorder.recorded == Array(repeating: ["hold", "clear"], count: 4).flatMap { $0 })
    }

    @Test("A pass cancelled before it starts still empties the cache")
    func cancelledPassClears() async {
        let recorder = CacheRecorder()
        let scorer = MLXCandidateScorer(model: .gemma3, maximumTokens: 16, bufferCache: recorder.control)
        let situation = situation
        let work = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await scorer.completions(for: "Thanks for sending", in: situation)
        }
        _ = try? await work.value
        #expect(recorder.recorded == ["hold", "clear"])
    }

    @Test("Releasing the model empties the cache and leaves nothing to answer with")
    func releaseClears() async {
        let recorder = CacheRecorder()
        let scorer = MLXCandidateScorer(model: .gemma3, maximumTokens: 16, bufferCache: recorder.control)
        await scorer.release()
        #expect(recorder.recorded == ["clear"])
        #expect(await scorer.isReady == false)
    }

    @Test("The cap is a quarter of a gigabyte")
    func limitIsMeasured() {
        #expect(GPUBufferCache.limit == 256 * 1_048_576)
    }
}
