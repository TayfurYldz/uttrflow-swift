// Tests that a stop racing a keystroke still delivers the press before the release it owes.
import Dispatch
import Foundation
import Synchronization
import Testing

@testable import UttrflowCore
@testable import UttrflowInput

/// A keyboard that hands strokes to the monitor on whichever thread calls `send`.
private final class HandFedSource: KeyboardEventSource {
    private struct Sink: Sendable {
        let call: @Sendable (KeyStroke) -> Void
    }

    private let sink = Mutex<Sink?>(nil)

    func start(_ deliver: @escaping @Sendable (KeyStroke) -> Void) throws(KeyboardSourceError) {
        sink.withLock { $0 = Sink(call: deliver) }
    }

    func stop() { sink.withLock { $0 = nil } }

    func send(_ stroke: KeyStroke) { sink.withLock { $0 }?.call(stroke) }
}

/// Holds the source's thread once its stroke has left the lock, until the test lets it go.
private final class Turnstile: Sendable {
    let arrived = DispatchSemaphore(value: 0)
    let proceed = DispatchSemaphore(value: 0)

    func hold() {
        arrived.signal()
        proceed.wait()
    }
}

private let optionSpaceDown = KeyStroke(keyCode: 49, modifiers: [.option], phase: .down)

/// Sends ⌥Space down on a thread of its own and runs `interrupt` while that stroke is held past the lock.
@MainActor
private func raceAPress(interrupt: (ActivationMonitor) throws -> Void) throws -> ActivationMonitor {
    let source = HandFedSource()
    let turnstile = Turnstile()
    let monitor = ActivationMonitor(source: source, strokeLeftLock: { turnstile.hold() })
    try monitor.start(binding: .optionSpace)

    let typed = DispatchSemaphore(value: 0)
    Thread {
        source.send(optionSpaceDown)
        typed.signal()
    }.start()

    turnstile.arrived.wait()
    try interrupt(monitor)
    turnstile.proceed.signal()
    typed.wait()
    monitor.stop()
    return monitor
}

/// The first two events the monitor delivered, which are already buffered when this is called.
private func firstTwo(_ monitor: ActivationMonitor) async -> [HotkeyEvent] {
    var events = monitor.events.makeAsyncIterator()
    var seen: [HotkeyEvent] = []
    for _ in 0..<2 {
        if let event = await events.next() { seen.append(event) }
    }
    return seen
}

@Suite("Activation monitor: stopping while a keystroke is in flight")
struct ActivationMonitorOrderTests {
    @Test("a stop during a press delivers the press before the release it owes")
    @MainActor
    func stopDuringPress() async throws {
        let events = await firstTwo(try raceAPress { $0.stop() })
        #expect(events == [.pressed, .released])
    }

    @Test("a rebind during a press delivers the press before the release it owes")
    @MainActor
    func rebindDuringPress() async throws {
        let events = await firstTwo(try raceAPress { try $0.start(binding: .optionSpace) })
        #expect(events == [.pressed, .released])
    }
}
