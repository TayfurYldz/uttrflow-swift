// The SpeechEngine the product uses, applying its rules over any TranscriptionBackend.
public import UttrflowCore

/// The one speech engine: every rule that outlives a choice of recogniser lives here.
public actor BackedSpeechEngine: SpeechEngine {
    /// Audio shorter than this cannot carry a word, and recognisers hallucinate on it.
    public static let minimumDuration = Duration.milliseconds(250)

    public nonisolated let kind: SpeechEngineKind

    private let backend: any TranscriptionBackend
    private var isLoaded = false
    /// One call into the recogniser at a time, since actor reentrancy lets a second in at every await. See `Docs/speech-engines.md`.
    private let turn = RecogniserTurn()

    public init(
        kind: SpeechEngineKind,
        backend: any TranscriptionBackend
    ) {
        self.kind = kind
        self.backend = backend
    }

    public func prepare() async throws(SpeechEngineError) {
        guard !isLoaded else { return }
        try await turn.take()
        defer { turn.release() }
        try await loadIfNeeded()
    }

    /// Loads the recogniser unless a call that held the turn earlier already did; the caller holds the turn.
    private func loadIfNeeded() async throws(SpeechEngineError) {
        guard !isLoaded else { return }
        try await backend.load()
        isLoaded = true
    }

    public func transcribe(
        _ audio: AudioSamples,
        options: TranscriptionOptions
    ) async throws(SpeechEngineError) -> Transcription {
        guard audio.duration >= Self.minimumDuration else { throw .audioTooShort }

        // Before the recogniser: nothing downstream can tell invented words from spoken ones.
        guard let speech = audio.speechOnly() else { throw .nothingHeard }
        guard speech.audio.duration >= Self.minimumDuration else { throw .nothingHeard }

        // Held until the recogniser answers, so an abandoned decode still running is waited for rather than overlapped.
        try await turn.take()
        defer { turn.release() }

        // A caller that forgot to prepare gets a slow first transcription, not a failure.
        try await loadIfNeeded()

        // Ranked once for the dictation and carried in, so every piece is biased towards the same words.
        let raw = try await backend.transcribe(
            Self.padded(speech.audio, to: backend.minimumDuration),
            languageHint: options.languageHint, biasedTowards: options.vocabulary)
        // The original duration, not the trimmed one: it is what the user spoke for.
        return raw.transcription(audioDuration: audio.duration, startingAt: speech.start)
    }

    /// The samples with silence appended up to `minimum`, so a word shorter than the recogniser's floor still decodes.
    static func padded(_ audio: AudioSamples, to minimum: Duration) -> [Float] {
        let needed = Int((minimum / .seconds(1) * Double(audio.sampleRate)).rounded(.up))
        guard audio.samples.count < needed else { return audio.samples }
        return audio.samples + Array(repeating: 0, count: needed - audio.samples.count)
    }
}
