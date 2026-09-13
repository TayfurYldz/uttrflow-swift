// Word timings for a prompted decode, read from the alignment rows the transcript actually occupies.
import CoreML
import WhisperKit

/// WhisperKit's segment seeker, handed alignment weights that start at the transcript rather than at the prompt. See `Docs/speech-engines.md`.
struct PromptAlignedSegmentSeeker: SegmentSeeking {
    /// The alignment row of the start-of-transcript token, which WhisperKit's seeker assumes is row zero.
    let transcriptStart: Int

    /// The seeker that does the work once the rows are lined up.
    let inner: any SegmentSeeking

    init(transcriptStart: Int, inner: any SegmentSeeking = SegmentSeeker()) {
        self.transcriptStart = transcriptStart
        self.inner = inner
    }

    func findSeekPointAndSegments(
        decodingResult: DecodingResult,
        options: DecodingOptions,
        allSegmentsCount: Int,
        currentSeek seek: Int,
        segmentSize: Int,
        sampleRate: Int,
        timeToken: Int,
        specialToken: Int,
        tokenizer: any WhisperTokenizer
    ) -> (Int, [TranscriptionSegment]?) {
        inner.findSeekPointAndSegments(
            decodingResult: decodingResult, options: options, allSegmentsCount: allSegmentsCount,
            currentSeek: seek, segmentSize: segmentSize, sampleRate: sampleRate, timeToken: timeToken,
            specialToken: specialToken, tokenizer: tokenizer)
    }

    func addWordTimestamps(
        segments: [TranscriptionSegment],
        alignmentWeights: MLMultiArray,
        tokenizer: any WhisperTokenizer,
        seek: Int,
        segmentSize: Int,
        prependPunctuations: String,
        appendPunctuations: String,
        lastSpeechTimestamp: Float,
        options: DecodingOptions,
        timings: TranscriptionTimings
    ) throws -> [TranscriptionSegment]? {
        try inner.addWordTimestamps(
            segments: segments,
            alignmentWeights: Self.rows(of: alignmentWeights, from: transcriptStart),
            tokenizer: tokenizer, seek: seek, segmentSize: segmentSize,
            prependPunctuations: prependPunctuations, appendPunctuations: appendPunctuations,
            lastSpeechTimestamp: lastSpeechTimestamp, options: options, timings: timings)
    }

    /// The weights with their first `first` rows removed and zero rows appended, so the shape is unchanged.
    static func rows(of weights: MLMultiArray, from first: Int) throws -> MLMultiArray {
        guard first > 0, weights.shape.count == 2 else { return weights }
        let rowCount = weights.shape[0].intValue
        let shifted = try MLMultiArray(shape: weights.shape, dataType: weights.dataType)
        let kept = max(0, rowCount - first)
        weights.withUnsafeBytes { source in
            shifted.withUnsafeMutableBytes { destination, _ in
                let rowBytes = source.count / max(rowCount, 1)
                destination.initializeMemory(as: UInt8.self, repeating: 0)
                if kept > 0, let from = source.baseAddress, let to = destination.baseAddress {
                    to.copyMemory(from: from.advanced(by: first * rowBytes), byteCount: kept * rowBytes)
                }
            }
        }
        return shifted
    }
}
