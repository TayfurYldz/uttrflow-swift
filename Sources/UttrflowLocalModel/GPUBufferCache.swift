import MLX

/// MLX's own count of the GPU memory it holds, in bytes.
public struct GPUMemoryReading: Sendable, Equatable {
    /// Buffers in use by arrays that are still alive, the model's weights among them.
    public let active: Int
    /// Freed buffers MLX keeps for reuse instead of handing back to the system.
    public let cache: Int
    /// The most active memory at any moment since the process started.
    public let peak: Int
}

/// Keeps MLX's GPU buffer cache from growing with every differently sized pass. See `Docs/performance.md`.
public enum GPUBufferCache {
    /// The most freed GPU memory MLX may keep for reuse, measured as costing a pass no time.
    public static let limit = 256 * 1_048_576

    /// What MLX holds right now.
    public static var reading: GPUMemoryReading {
        GPUMemoryReading(active: Memory.activeMemory, cache: Memory.cacheMemory, peak: Memory.peakMemory)
    }
}

/// What a model does to MLX's buffer cache around each pass, as a value so a test can watch it without a GPU.
struct BufferCacheControl: Sendable {
    /// Caps the cache at the limit for the whole process, which covers buffers a cancelled pass frees late.
    let hold: @Sendable () -> Void
    /// Hands every cached buffer back to the system, so nothing a pass freed outlives it.
    let clear: @Sendable () -> Void

    /// The real cache, which only a process that loaded MLX's Metal library may touch.
    static let mlx = BufferCacheControl(
        hold: { Memory.cacheLimit = GPUBufferCache.limit }, clear: { Memory.clearCache() })
}
