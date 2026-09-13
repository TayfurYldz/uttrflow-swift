/// Cleans a raw transcript into the text the user meant, never changing the meaning; unsure means unchanged.
public protocol TextTransformationEngine: Sendable {
    /// Which kind this engine is, for routing and for tagging its output.
    var kind: TransformerKind { get }

    /// Whether this engine can handle this request, chiefly whether it supports the detected language.
    func availability(for request: TransformationRequest) async -> TransformerAvailability

    /// Cleans one utterance, or throws when it cannot rather than producing poor output.
    func transform(
        _ request: TransformationRequest
    ) async throws(TransformationError) -> TransformationResult

    /// Gets ready for a request going to `situation`, or to nowhere known, so the first one is not the slow one.
    func warm(for situation: Situation?) async

    /// How long this engine may take before the router steps to the next one. See `Docs/stuck-recording.md`.
    var budget: Duration { get }
}

/// The defaults: nothing to warm, and a model's allowance.
extension TextTransformationEngine {
    /// What an engine that has not said otherwise may take, which is what a model engine needs.
    public var budget: Duration { StageTimeout.engine }

    /// Nothing to prepare, which is what a rule-based engine has.
    public func warm(for situation: Situation?) async {}
}
