import ArgumentParser
import Foundation
import UttrflowEval

/// Prints how a run's memory readings sit against the budget, and fails the command when any is over. See `Docs/performance.md`.
enum BudgetVerdict {
    static func enforce(_ readings: [BudgetReading]) throws {
        let breaches = ResourceBudget.breaches(in: readings)
        let highest = Dictionary(grouping: readings, by: \.state).mapValues {
            $0.map(\.footprintBytes).max() ?? 0
        }
        print("\nMemory budget")
        for state in BudgetedState.allCases {
            guard let bytes = highest[state] else { continue }
            let mark = bytes > state.limitInBytes ? "✗" : "✓"
            print(
                "  \(mark) \(state.rawValue): highest \(bytes / 1_048_576) MB of \(state.limitInMegabytes) MB"
            )
        }
        guard !breaches.isEmpty else { return }
        for breach in breaches {
            FileHandle.standardError.write(Data("  ✗ \(breach)\n".utf8))
        }
        throw ExitCode.failure
    }
}
