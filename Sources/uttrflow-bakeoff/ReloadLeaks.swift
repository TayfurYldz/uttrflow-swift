import ArgumentParser
import Foundation
import UttrflowEval
import UttrflowLocalModel
import UttrflowPredict

/// Releases and reloads the suggestion model many times in one process and runs `leaks` on it between batches. See `Docs/performance.md`.
struct ReloadLeaks: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reload-leaks",
        abstract: "Release and reload the suggestion model, reporting leaks, footprint and reload time."
    )

    @Option(name: .long, help: "Comma-separated running totals of reloads at which to run leaks.")
    var checkpoints = "1,5,20"

    @Option(name: .long, help: "Which model to run, by repository or short name.")
    var model = LocalModel.gemma3.identifier

    func run() async throws {
        guard let chosen = LocalModel.named(model) else {
            throw ValidationError("Unknown model '\(model)'.")
        }
        let totals = checkpoints.split(separator: ",").compactMap { Int($0) }
        guard !totals.isEmpty, totals == totals.sorted() else {
            throw ValidationError("Checkpoints must be ascending whole numbers.")
        }
        let scorer = MLXCandidateScorer(model: chosen)
        let started = ContinuousClock.now
        try await scorer.prepare()
        let first = Self.milliseconds(since: started)
        let expected = try await Self.answer(from: scorer)
        print("first load \(first) ms  \(Self.footprint())  \(Self.leaks())")
        var done = 0
        var times: [Int] = []
        for total in totals {
            while done < total {
                await scorer.release()
                let released = Self.footprint()
                let reloading = ContinuousClock.now
                try await scorer.prepare()
                times.append(Self.milliseconds(since: reloading))
                done += 1
                if done == total { print("  last release: \(released)") }
            }
            let same = try await Self.answer(from: scorer) == expected
            let sorted = times.sorted()
            print(
                "reloads \(String(done).leftPadded(to: 3))  median reload \(sorted[sorted.count / 2]) ms  "
                    + "\(Self.footprint())  \(Self.leaks())  same answer \(same)")
        }
    }

    /// One fixed generation, so a reload that loaded the wrong weights shows as a different answer.
    private static func answer(from scorer: MLXCandidateScorer) async throws -> [String] {
        let situation = GenerationSituation(
            application: "Mail", windowTitle: "Re: planning",
            surroundings: "Could we move the review to Thursday? The venue is booked on Wednesday.",
            isMultiline: true)
        return try await scorer.completions(for: "Thursday works, I will ", in: situation)
    }

    private static func milliseconds(since start: ContinuousClock.Instant) -> Int {
        Int((ContinuousClock.now - start) / .milliseconds(1))
    }

    /// The process's footprint, which is what Activity Monitor shows.
    private static func footprint() -> String {
        "footprint \(String((MemoryFootprint.current() ?? 0) / 1_048_576).leftPadded(to: 6)) MB"
    }

    /// The summary line `leaks` prints for this process, or why there is none.
    private static func leaks() -> String {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/leaks")
        process.arguments = [String(ProcessInfo.processInfo.processIdentifier)]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return "leaks did not run: \(error)" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        let summary = text.split(separator: "\n").first {
            $0.contains("leaks for") && $0.contains("total leaked bytes")
        }
        return summary.map { $0.trimmingCharacters(in: .whitespaces) } ?? "no leaks summary"
    }
}
