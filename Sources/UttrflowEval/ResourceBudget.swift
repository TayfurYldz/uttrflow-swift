// Judges memory readings against the budget in Docs/performance.md.

/// A moment the memory budget names a limit for.
public enum BudgetedState: String, Sendable, Equatable, CaseIterable {
    /// The app idle with suggestions off, the speech model loaded.
    case idleSuggestionsOff
    /// The highest footprint during a dictation, suggestions off.
    case dictationPeak
    /// Suggestions on, between one pass and the next.
    case suggestionsBetweenPasses
    /// Suggestions on, the highest footprint inside a pass.
    case suggestionsPassPeak
    /// A second after the suggestion model is released, which must be back on the idle line.
    case afterRelease

    /// The most footprint this state may hold, in megabytes, as the budget table in Docs/performance.md states it.
    public var limitInMegabytes: Int64 {
        switch self {
        case .idleSuggestionsOff: return 300
        case .dictationPeak: return 400
        case .suggestionsBetweenPasses: return 3_072
        case .suggestionsPassPeak: return 3_584
        case .afterRelease: return BudgetedState.idleSuggestionsOff.limitInMegabytes
        }
    }

    /// The limit in bytes.
    public var limitInBytes: Int64 { limitInMegabytes * 1_048_576 }
}

/// One footprint reading taken in a budgeted state, with the label a report prints beside it.
public struct BudgetReading: Sendable, Equatable {
    public let state: BudgetedState
    public let label: String
    public let footprintBytes: Int64

    public init(state: BudgetedState, label: String, footprintBytes: Int64) {
        self.state = state
        self.label = label
        self.footprintBytes = footprintBytes
    }
}

/// A reading over its state's limit.
public struct BudgetBreach: Sendable, Equatable, CustomStringConvertible {
    public let reading: BudgetReading

    /// How far over the limit the reading is, in bytes.
    public var excessBytes: Int64 { reading.footprintBytes - reading.state.limitInBytes }

    public var description: String {
        let megabytes = reading.footprintBytes / 1_048_576
        return
            "\(reading.label): \(megabytes) MB footprint, over the \(reading.state.limitInMegabytes) MB budget for \(reading.state.rawValue)"
    }
}

/// The memory budget as a judge: readings in, breaches out, so a harness fails rather than prints.
public enum ResourceBudget {
    /// Every reading over its state's limit, in the order they were taken.
    public static func breaches(in readings: [BudgetReading]) -> [BudgetBreach] {
        readings.filter { $0.footprintBytes > $0.state.limitInBytes }.map(BudgetBreach.init)
    }
}

extension ResourceBudget {
    /// A dictation profile's readings: every named moment is idle with suggestions off, and its peak is a dictation's.
    public static func readings(of timeline: MemoryTimeline) -> [BudgetReading] {
        let settled = timeline.samples.map {
            BudgetReading(
                state: .idleSuggestionsOff, label: $0.label, footprintBytes: $0.reading.footprintBytes)
        }
        let peak = timeline.peak.map {
            BudgetReading(
                state: .dictationPeak, label: "peak, mid-dictation", footprintBytes: $0.footprintBytes)
        }
        return settled + (peak.map { [$0] } ?? [])
    }
}
