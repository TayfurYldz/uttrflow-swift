import Dispatch
import UttrflowCore
import Testing

@testable import UttrflowInput

/// A shortcut is re-registered through the real monitor without ever colliding with itself. See `Docs/shortcuts.md`.
@MainActor
@Suite("Re-registering a shortcut", .serialized)
struct CarbonHotkeyLifecycleTests {
    /// F13 and F15 with three modifiers: nothing on a stock Mac claims either.
    private let bound = HotkeyBinding(keyCode: 105, modifiers: [.control, .option, .shift])
    private let away = HotkeyBinding(keyCode: 113, modifiers: [.control, .option, .shift])

    @Test("bind, change away, change back and activate leaves exactly one registration")
    func changeAwayAndBack() throws {
        var current = CarbonHotkeyMonitor()
        try current.start(binding: bound)
        for binding in [away, bound, bound] {
            current.stop()
            current = CarbonHotkeyMonitor()
            try current.start(binding: binding)
        }
        defer { current.stop() }
        try expectHeld(bound)
    }

    @Test("a monitor stopped off the main thread does not refuse the next registration")
    func stopOffMainThenRebind() async throws {
        let previous = CarbonHotkeyMonitor()
        let next = CarbonHotkeyMonitor()
        defer { next.stop() }
        try previous.start(binding: bound)

        try stopOffMainThenStart(previous, next)
        await mainQueueDrained()

        try expectHeld(bound)
    }

    /// Stops on another thread while the main thread waits, so a deferred unregister has not run yet.
    private func stopOffMainThenStart(
        _ previous: CarbonHotkeyMonitor, _ next: CarbonHotkeyMonitor
    ) throws {
        let stopped = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            previous.stop()
            stopped.signal()
        }
        stopped.wait()
        try next.start(binding: bound)
    }

    /// Returns once every block queued on the main queue before it has run.
    private func mainQueueDrained() async {
        await withCheckedContinuation { (resumed: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async { resumed.resume() }
        }
    }

    /// Carbon refuses a second registration in this process only while the first still holds the key.
    private func expectHeld(_ binding: HotkeyBinding) throws {
        let intruder = CarbonHotkeyMonitor()
        defer { intruder.stop() }
        #expect(throws: HotkeyError.shortcutUnavailable) {
            try intruder.start(binding: binding)
        }
    }
}
