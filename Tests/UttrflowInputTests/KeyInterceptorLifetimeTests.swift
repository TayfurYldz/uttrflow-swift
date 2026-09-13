// Tests that a stopped key tap gives back the port and the state it held.
import CoreFoundation
import Dispatch
import Foundation
import Testing

@testable import UttrflowInput

@Suite("The key interceptor's tap lifetime")
struct KeyInterceptorLifetimeTests {
    /// A plain Mach port, which stands in for an event tap without needing Accessibility.
    private static func makePort() -> CFMachPort? {
        CFMachPortCreate(nil, { _, _, _, _ in }, nil, nil)
    }

    /// A state with a resumed source of its own, since libdispatch traps on freeing a suspended one.
    private static func makeState() -> TapState {
        let source = DispatchSource.makeUserDataAddSource(queue: DispatchQueue(label: "test.tap-state"))
        source.resume()
        return TapState(signal: source)
    }

    /// Polls until the condition holds or two seconds pass, since a tap's thread winds down on its own.
    private static func eventually(_ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(2)
        while !condition() {
            if Date() > deadline { return false }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return true
    }

    /// Starts and stops one tap on the port, keeping no reference to the tap afterwards.
    private static func cycle(state: TapState, port: CFMachPort) throws {
        let tap = try InterceptorTap.create(state: state) { _ in port }
        tap.run()
        tap.stop()
    }

    @Test("a start, stop and start leaves the first port's retain count where it began")
    func restartingReleasesThePreviousPort() throws {
        let state = Self.makeState()
        let first = try #require(Self.makePort())
        let second = try #require(Self.makePort())
        let baseline = CFGetRetainCount(first)

        try Self.cycle(state: state, port: first)
        try Self.cycle(state: state, port: second)

        #expect(
            Self.eventually { CFGetRetainCount(first) == baseline },
            "retain count \(CFGetRetainCount(first)) vs \(baseline)")
    }

    @Test("adopting a new port releases the one it replaces")
    func adoptingReleasesTheReplacedPort() throws {
        let state = Self.makeState()
        let first = try #require(Self.makePort())
        let second = try #require(Self.makePort())
        let baseline = CFGetRetainCount(first)

        state.adopt(first)
        state.adopt(second)

        #expect(CFGetRetainCount(first) == baseline, "retain count \(CFGetRetainCount(first)) vs \(baseline)")
    }

    @Test("a stopped tap releases the port it gave the state")
    func stoppingReleasesThePort() throws {
        let state = Self.makeState()
        let port = try #require(Self.makePort())
        let baseline = CFGetRetainCount(port)

        try Self.cycle(state: state, port: port)

        #expect(
            Self.eventually { CFGetRetainCount(port) == baseline },
            "retain count \(CFGetRetainCount(port)) vs \(baseline)")
        withExtendedLifetime(state) {}
    }

    @Test("a running tap keeps its state alive, and a stopped one lets it go")
    func runningTapHoldsTheState() throws {
        let port = try #require(Self.makePort())
        weak var weakState: TapState?
        var tap: InterceptorTap?
        do {
            let state = Self.makeState()
            weakState = state
            tap = try InterceptorTap.create(state: state) { _ in port }
        }
        tap?.run()
        #expect(weakState != nil, "the state was freed while its tap was running")
        tap?.stop()
        tap = nil
        #expect(Self.eventually { weakState == nil }, "the state outlived its stopped tap")
    }

    @Test("a tap stopped before it runs still releases its state")
    func stoppingBeforeRunningReleasesTheState() throws {
        let port = try #require(Self.makePort())
        weak var weakState: TapState?
        var tap: InterceptorTap?
        do {
            let state = Self.makeState()
            weakState = state
            tap = try InterceptorTap.create(state: state) { _ in port }
        }
        tap?.stop()
        tap?.run()
        tap = nil
        #expect(Self.eventually { weakState == nil }, "the state outlived a tap stopped before it ran")
    }

    @Test("a refused tap takes nothing from the state")
    func refusedTapThrows() {
        let state = Self.makeState()
        #expect(throws: KeyInterceptorFailure.tapRefused) {
            try InterceptorTap.create(state: state) { _ in nil }
        }
    }
}
