// A count of work done, which a test can bound where a clock would flake.
private import Synchronization

/// Counts units of work while a test has it bound, so cost is bounded by what was done rather than how long it took.
package final class WorkTally: Sendable {
    private let done = Mutex(0)

    package init() {}

    /// The units counted so far.
    package var count: Int { done.withLock { $0 } }

    /// Adds `units` to the count, from whichever thread did the work.
    package func record(_ units: Int = 1) { done.withLock { $0 += units } }
}
