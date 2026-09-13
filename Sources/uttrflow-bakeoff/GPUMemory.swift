import ArgumentParser
import Foundation
import UttrflowLocalModel
import UttrflowPredict

/// Runs the suggestion model over many differently sized moments, some cancelled, and reports MLX's GPU memory after each. See `Docs/performance.md`.
struct GPUMemory: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "gpu-memory",
        abstract: "Run varied suggestion passes, cancelling some, and print MLX's GPU memory after each."
    )

    @Option(name: .long, help: "How many passes to run.")
    var passes = 40

    @Option(name: .long, help: "Cancel every Nth pass part-way through; 0 cancels none.")
    var cancelEvery = 4

    @Option(name: .long, help: "Which model to run, by repository or short name.")
    var model = LocalModel.gemma3.identifier

    /// How each invented line opens, so the typed text differs from pass to pass as well as the screen.
    private static let openings = [
        "Thanks for sending this over, I will ", "Could we move the review to ", "Sounds good, let",
    ]

    func run() async throws {
        guard let chosen = LocalModel.named(model) else {
            throw ValidationError("Unknown model '\(model)'.")
        }
        let scorer = MLXCandidateScorer(model: chosen)
        try await scorer.prepare()
        print("loaded                    \(Self.row(GPUBufferCache.reading))")
        var times: [Int] = []
        for pass in 1...passes {
            let cancelled = cancelEvery > 0 && pass % cancelEvery == 0
            let elapsed = await Self.measure(pass: pass, cancelled: cancelled, with: scorer)
            if !cancelled { times.append(elapsed) }
            let kind = cancelled ? "cancelled" : "complete "
            let label =
                "pass \(String(pass).leftPadded(to: 3)) \(kind) \(String(elapsed).leftPadded(to: 5)) ms"
            print("\(label)  \(Self.row(GPUBufferCache.reading))")
        }
        try? await Task.sleep(for: .seconds(5))
        print("idle 5 s                  \(Self.row(GPUBufferCache.reading))")
        let sorted = times.sorted()
        guard !sorted.isEmpty else { return }
        print(
            "complete passes: median \(sorted[sorted.count / 2]) ms, mean \(sorted.reduce(0, +) / sorted.count) ms"
        )
    }

    /// One generation pass, cancelled part-way when asked, then one score; returns the milliseconds both took.
    private static func measure(pass: Int, cancelled: Bool, with scorer: MLXCandidateScorer) async -> Int {
        let situation = GenerationSituation(
            application: "Mail", windowTitle: "Re: planning",
            surroundings: thread(words: 120 + pass * 37 % 190),
            isMultiline: true)
        let typed = openings[pass % openings.count] + String(repeating: "and then ", count: pass % 5)
        let started = ContinuousClock.now
        let work = Task { try await scorer.completions(for: typed, in: situation) }
        if cancelled {
            try? await Task.sleep(for: .milliseconds(40 + pass * 13 % 120))
            work.cancel()
        }
        _ = try? await work.value
        _ = await scorer.judgedTokens(of: typed + thread(words: 4 + pass % 23), following: typed)
        return Int((ContinuousClock.now - started) / .milliseconds(1))
    }

    /// Active, cache and peak memory in megabytes, in fixed columns.
    private static func row(_ reading: GPUMemoryReading) -> String {
        let columns = [("active", reading.active), ("cache", reading.cache), ("peak", reading.peak)]
        return columns.map { "\($0.0) \(String($0.1 / 1_048_576).leftPadded(to: 6)) MB" }.joined(
            separator: "  ")
    }

    /// An invented message thread of about this many words, so each pass reads a prompt of a different length.
    private static func thread(words count: Int) -> String {
        let words = [
            "the", "draft", "schedule", "for", "next", "week", "looks", "fine", "but", "we", "should",
            "check",
            "whether", "the", "venue", "can", "hold", "everyone", "and", "send", "the", "agenda", "early",
        ]
        return (0..<count).map { words[($0 * 7 + count) % words.count] }.joined(separator: " ")
    }
}
