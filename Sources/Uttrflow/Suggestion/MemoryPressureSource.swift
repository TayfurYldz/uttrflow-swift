// Reads macOS's memory pressure from the kernel.

import Dispatch

/// Reports each change in memory pressure on the main actor. See `Docs/performance.md`.
@MainActor
final class MemoryPressureSource {
    private var source: (any DispatchSourceMemoryPressure)?

    /// Whether a watch is running.
    var isWatching: Bool { source != nil }

    /// Starts watching, replacing any watch already running.
    func start(_ onChange: @escaping @MainActor (MemoryPressureLevel) -> Void) {
        stop()
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.normal, .warning, .critical], queue: .main)
        source.setEventHandler { [weak source] in
            guard let event = source?.data else { return }
            MainActor.assumeIsolated { onChange(MemoryPressureLevel(event)) }
        }
        source.activate()
        self.source = source
    }

    /// Stops watching.
    func stop() {
        source?.cancel()
        source = nil
    }
}
