// Tests the memory budget's judge.
import Testing

@testable import UttrflowEval

@Suite("Resource budget")
struct ResourceBudgetTests {
    private let megabyte: Int64 = 1_048_576

    private func reading(_ state: BudgetedState, _ megabytes: Int64) -> BudgetReading {
        BudgetReading(state: state, label: state.rawValue, footprintBytes: megabytes * megabyte)
    }

    @Test("the limits are the budget table's")
    func limitsMatchTheTable() {
        #expect(BudgetedState.idleSuggestionsOff.limitInMegabytes == 300)
        #expect(BudgetedState.dictationPeak.limitInMegabytes == 400)
        #expect(BudgetedState.suggestionsBetweenPasses.limitInMegabytes == 3_072)
        #expect(BudgetedState.suggestionsPassPeak.limitInMegabytes == 3_584)
        #expect(BudgetedState.afterRelease.limitInBytes == 300 * megabyte)
    }

    @Test("a reading at its limit is inside the budget")
    func atTheLimitPasses() {
        let readings = BudgetedState.allCases.map { reading($0, $0.limitInMegabytes) }
        #expect(ResourceBudget.breaches(in: readings).isEmpty)
    }

    @Test("a reading one byte over its limit is a breach, and only that one")
    func overTheLimitFails() {
        let over = BudgetReading(
            state: .dictationPeak, label: "dictation 7", footprintBytes: 400 * megabyte + 1)
        let breaches = ResourceBudget.breaches(in: [reading(.idleSuggestionsOff, 120), over])
        #expect(breaches == [BudgetBreach(reading: over)])
        #expect(breaches.first?.excessBytes == 1)
        #expect(over.isOverBudget)
        #expect(!reading(.dictationPeak, 400).isOverBudget)
    }

    @Test("a release that leaves the model behind breaches the idle line")
    func releaseMustReturnToIdle() {
        let breaches = ResourceBudget.breaches(in: [reading(.afterRelease, 2_600)])
        #expect(breaches.count == 1)
        #expect(
            breaches.first?.description
                == "afterRelease: 2600 MB footprint, over the 300 MB budget for afterRelease")
    }

    @Test("breaches come back in the order the readings were taken")
    func orderIsKept() {
        let first = reading(.suggestionsBetweenPasses, 3_100)
        let second = reading(.suggestionsPassPeak, 4_000)
        #expect(ResourceBudget.breaches(in: [first, second]).map(\.reading) == [first, second])
    }
}

@Suite("Resource budget of a dictation profile")
struct ResourceBudgetProfileTests {
    private let megabyte: Int64 = 1_048_576

    private func sample(_ label: String, _ megabytes: Int64) -> MemorySample {
        MemorySample(
            label: label,
            reading: MemoryReading(footprintBytes: megabytes * megabyte, residentBytes: megabytes * megabyte))
    }

    @Test("named moments are judged as idle and the peak as a dictation's")
    func statesFollowTheTimeline() {
        let timeline = MemoryTimeline(
            samples: [sample("speech model loaded", 230), sample("after 10 dictations", 310)],
            peak: MemoryReading(footprintBytes: 420 * megabyte, residentBytes: 0))
        let readings = ResourceBudget.readings(of: timeline)
        #expect(readings.map(\.state) == [.idleSuggestionsOff, .idleSuggestionsOff, .dictationPeak])
        #expect(
            ResourceBudget.breaches(in: readings).map(\.reading.label) == [
                "after 10 dictations", "peak, mid-dictation",
            ])
    }

    @Test("a timeline with no peak yields only its named moments")
    func noPeak() {
        let readings = ResourceBudget.readings(
            of: MemoryTimeline(samples: [sample("idle, nothing loaded", 11)], peak: nil))
        #expect(readings.map(\.label) == ["idle, nothing loaded"])
        #expect(ResourceBudget.breaches(in: readings).isEmpty)
    }
}
