// Lets a loaded model go when nothing has asked for it in a while, and loads it again when something does.

import Foundation

/// A model that can be loaded and let go, which is all an idle release needs of one.
public protocol ReleasableModel: CandidateScoring, CandidateGenerating {
    /// Loads the weights, reporting how far along the fetch is.
    func prepare(onProgress: @escaping @Sendable (Double) -> Void) async throws
    /// Drops the weights.
    func release() async
}

/// How long a suggestion model may sit unasked before it is let go. See `Docs/performance.md`.
public enum IdleRelease {
    /// The window on a Mac with at least 16 GB.
    public static let roomy = Duration.seconds(600)
    /// The window on a Mac with less.
    public static let tight = Duration.seconds(180)

    /// The window for a Mac with this much physical memory, in bytes.
    public static func window(physicalMemory: UInt64) -> Duration {
        physicalMemory < 16 * 1_073_741_824 ? tight : roomy
    }
}

/// Holds a model only while something keeps asking for it; a release by the caller is never undone by a query.
public actor IdleReleasingModel<Model: ReleasableModel>: ReleasableModel {
    private let model: Model
    private let idleAfter: Duration
    /// Whether the caller wants the model, which only ``prepare(onProgress:)`` and ``release()`` change.
    private var isWanted = false
    /// Whether the weights are loaded or loading, so a query does not start a second load.
    private var isHeld = false
    private var lastAsked = ContinuousClock.now
    /// The latest load or release, which the next one waits for so they land in the order they were asked.
    private var work: Task<Void, Never>?
    private var watch: Task<Void, Never>?

    public init(model: Model, idleAfter: Duration) {
        self.model = model
        self.idleAfter = idleAfter
    }

    /// Whether the weights are loaded or on their way; internal so a test can read it.
    var holdsTheModel: Bool { isHeld }

    public func prepare(onProgress: @escaping @Sendable (Double) -> Void) async throws {
        isWanted = true
        isHeld = true
        lastAsked = .now
        let previous = work
        let model = model
        let step = Task { () -> (any Error)? in
            await previous?.value
            do {
                try await model.prepare(onProgress: onProgress)
                return nil
            } catch {
                return error
            }
        }
        work = Task { _ = await step.value }
        if let error = await step.value {
            isHeld = false
            throw error
        }
        watchForIdle()
    }

    public func release() async {
        isWanted = false
        isHeld = false
        watch?.cancel()
        let previous = work
        let model = model
        let step = Task {
            await previous?.value
            await model.release()
        }
        work = step
        await step.value
    }

    /// Whether the model can answer now, loading it again in the background when an idle release let it go.
    public var isReady: Bool {
        get async {
            lastAsked = .now
            if await model.isReady { return true }
            if isWanted, !isHeld { reload() }
            return false
        }
    }

    public func completions(for typed: String, in situation: GenerationSituation) async throws -> [String] {
        lastAsked = .now
        return try await model.completions(for: typed, in: situation)
    }

    public func alternatives(
        for typed: String, in situation: GenerationSituation, excluding leader: String
    ) async throws -> [String] {
        lastAsked = .now
        return try await model.alternatives(for: typed, in: situation, excluding: leader)
    }

    public func logLikelihood(of candidate: String, following context: String) async -> Double? {
        lastAsked = .now
        return await model.logLikelihood(of: candidate, following: context)
    }

    /// Lets the model go when it has not been asked for in the window; returns whether it is still held.
    @discardableResult
    func releaseIfIdle(at now: ContinuousClock.Instant) async -> Bool {
        guard isHeld else { return false }
        guard isWanted, lastAsked.duration(to: now) >= idleAfter else { return true }
        isHeld = false
        let previous = work
        let model = model
        let step = Task {
            await previous?.value
            await model.release()
        }
        work = step
        await step.value
        return false
    }

    /// The idle watch, which ends once it lets the model go; internal so a test can wait for it.
    var watching: Task<Void, Never>? { watch }

    /// The background load a query starts; internal so a test can wait for it.
    var pendingWork: Task<Void, Never>? { work }

    private func reload() {
        isHeld = true
        let previous = work
        let model = model
        work = Task { [weak self] in
            await previous?.value
            do {
                try await model.prepare(onProgress: { _ in })
                await self?.watchForIdle()
            } catch {
                await self?.loadFailed()
            }
        }
    }

    private func loadFailed() { isHeld = false }

    /// Checks for idleness a few times per window for as long as the model is held.
    private func watchForIdle() {
        watch?.cancel()
        let interval = idleAfter / 4
        watch = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled, let self, await releaseIfIdle(at: .now) else { return }
            }
        }
    }
}
