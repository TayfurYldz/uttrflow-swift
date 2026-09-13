// Tests that reading the microphone's hardware-change handler costs the same stack however often it is read.
import Testing

@testable import UttrflowAudio

@Suite("The microphone's hardware-change handler")
struct ChangeHandlerTests {
    /// The address of a local in a frame of its own, which is how deep the stack is where it is called.
    @inline(never)
    private static func stackAddress() -> Int {
        var marker: UInt8 = 0
        return withUnsafeMutablePointer(to: &marker) { Int(bitPattern: $0) }
    }

    /// Where the handler found the stack, written and read on the test's own thread.
    private final class Depth: @unchecked Sendable {
        var address = 0
    }

    @Test("the handler read at the 500th open runs no deeper in the stack than the one read at the first")
    func readingDoesNotDeepenTheStack() {
        let handler = ChangeHandler()
        let depth = Depth()
        handler.set { depth.address = ChangeHandlerTests.stackAddress() }

        var first = 0
        for count in 1...500 {
            handler.current()?()
            if count == 1 { first = depth.address }
        }

        #expect(first != 0, "the handler was never called")
        let growth = first - depth.address
        #expect(growth < 4096, "stack growth, read 1 -> read 500: \(growth) bytes")
    }

    @Test("nothing is handed back before a handler is set")
    func emptyUntilSet() {
        #expect(ChangeHandler().current() == nil)
    }
}
