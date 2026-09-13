// Tests that handing a keystroke to the keyboard's sink costs the same stack however many came before.
import CoreGraphics
import Testing

@testable import UttrflowInput

@Suite("Delivering keystrokes to the keyboard's sink")
struct SystemKeyboardDeliveryTests {
    /// The address of a local in a frame of its own, which is how deep the stack is where it is called.
    @inline(never)
    private static func stackAddress() -> Int {
        var marker: UInt8 = 0
        return withUnsafeMutablePointer(to: &marker) { Int(bitPattern: $0) }
    }

    /// Where the last callee found the stack, written and read on the test's own thread.
    private final class Depth: @unchecked Sendable {
        var address = 0
    }

    /// Records how deep the stack was when it is freed, so a release that recurses shows up as depth.
    private final class Witness: @unchecked Sendable {
        let depth: Depth

        init(depth: Depth) { self.depth = depth }

        deinit { depth.address = SystemKeyboardDeliveryTests.stackAddress() }
    }

    private let stroke = SystemKeyboard.stroke(keyCode: 0, flags: [], phase: .down)

    @Test("the 500th keystroke reaches the sink no deeper in the stack than the first")
    func sendingDoesNotDeepenTheStack() {
        let delivery = Delivery()
        let depth = Depth()
        delivery.set { _ in depth.address = SystemKeyboardDeliveryTests.stackAddress() }

        var first = 0
        for count in 1...500 {
            delivery.send(stroke)
            if count == 1 { first = depth.address }
        }

        let growth = first - depth.address
        #expect(growth < 4096, "stack growth, stroke 1 -> stroke 500: \(growth) bytes")
    }

    @Test("releasing the sink after 500 keystrokes frees it no deeper in the stack than after one")
    func releasingDoesNotRecurse() {
        let afterOne = releaseDepth(afterSending: 1)
        let afterMany = releaseDepth(afterSending: 500)
        #expect(afterOne != 0 && afterMany != 0, "the sink's captures were not freed by set(nil)")
        let growth = afterOne - afterMany
        #expect(growth < 4096, "release depth, after 1 stroke -> after 500 strokes: \(growth) bytes")
    }

    /// The stack address the sink's captures are freed at, when `set(nil)` follows this many sends.
    @inline(never)
    private func releaseDepth(afterSending count: Int) -> Int {
        let delivery = Delivery()
        let depth = Depth()
        delivery.set { [witness = Witness(depth: depth)] _ in withExtendedLifetime(witness) {} }
        for _ in 0..<count { delivery.send(stroke) }
        delivery.set(nil)
        return depth.address
    }
}
