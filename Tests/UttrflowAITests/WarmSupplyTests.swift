// Tests for the supply that keeps one prepared thing ready for whoever asks next.

import Synchronization
import Testing

@testable import UttrflowAI

@Suite("Keeping one ready")
struct WarmSupplyTests {
    /// Counts what it made, since the whole point is how often something expensive is built.
    private func supply(counting made: Mutex<[String]>) -> WarmSupply<String> {
        WarmSupply { key in
            made.withLock { $0.append(key) }
            return "session for \(key)"
        }
    }

    @Test("hands out the one it was asked to make ahead of time")
    func handsOutWhatItPrepared() async {
        let made = Mutex<[String]>([])
        let supply = supply(counting: made)
        await supply.replenish(for: "plain")

        #expect(await supply.take(for: "plain") == "session for plain")
        #expect(made.withLock { $0 } == ["plain"])
    }

    @Test("hands the same one out once only")
    func handsItOutOnce() async {
        let supply = supply(counting: Mutex([]))
        await supply.replenish(for: "plain")

        #expect(await supply.take(for: "plain") != nil)
        #expect(await supply.take(for: "plain") == nil)
    }

    /// The piece after the first is what this exists for: it must not have to make its own.
    @Test("has another ready once the one it had is taken and used")
    func replenishesAfterUse() async {
        let made = Mutex<[String]>([])
        let supply = supply(counting: made)
        await supply.replenish(for: "plain")

        _ = await supply.take(for: "plain")
        await supply.replenish(for: "plain")

        #expect(await supply.isReady(for: "plain"))
        #expect(await supply.take(for: "plain") == "session for plain")
        #expect(made.withLock { $0 } == ["plain", "plain"])
    }

    /// Warming twice for one dictation should not build twice; the second call has nothing to do.
    @Test("makes nothing when one is already waiting for the same request")
    func doesNotRemakeWhatIsAlreadyThere() async {
        let made = Mutex<[String]>([])
        let supply = supply(counting: made)

        await supply.replenish(for: "plain")
        await supply.replenish(for: "plain")

        #expect(made.withLock { $0 } == ["plain"])
    }

    /// A dictation into somewhere else carries different instructions, and the old one is no use to it.
    @Test("refuses the one it holds to a request that carries something else")
    func refusesAMismatch() async {
        let supply = supply(counting: Mutex([]))
        await supply.replenish(for: "plain")

        #expect(await supply.take(for: "messaging") == nil)
        #expect(await supply.isReady(for: "plain") == false, "the mismatched one is not kept waiting")
    }

    @Test("replaces what it holds when the next request carries something else")
    func replacesOnANewRequest() async {
        let made = Mutex<[String]>([])
        let supply = supply(counting: made)
        await supply.replenish(for: "plain")

        await supply.replenish(for: "messaging")

        #expect(await supply.take(for: "messaging") == "session for messaging")
        #expect(made.withLock { $0 } == ["plain", "messaging"])
    }

    @Test("keeps one handed to it, for the caller that made its own")
    func keepsWhatItIsGiven() async {
        let supply = supply(counting: Mutex([]))

        await supply.keep("made elsewhere", for: "plain")

        #expect(await supply.take(for: "plain") == "made elsewhere")
    }
}
