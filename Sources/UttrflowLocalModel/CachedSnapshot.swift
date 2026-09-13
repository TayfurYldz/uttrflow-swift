// Finds a model already whole in the local Hugging Face cache, so loading it asks nothing of the network.
import Foundation
import MLXLMCommon

/// A model's snapshot in the local Hugging Face cache, trusted only when every file it needs is whole.
enum CachedSnapshot {
    /// The files every snapshot needs besides its weights: the architecture and the tokenizer.
    static let requiredFiles = ["config.json", "tokenizer.json", "tokenizer_config.json"]

    /// The largest safetensors header believed, so a corrupt length cannot ask for gigabytes.
    static let largestHeader: UInt64 = 100_000_000

    /// The snapshot of `identifier` in `cache` when its files are whole and its weights heavy enough.
    static func complete(identifier: String, in cache: URL, minimumWeightBytes: UInt64) -> URL? {
        let repository = cache.appending(
            path: "models--" + identifier.replacingOccurrences(of: "/", with: "--"),
            directoryHint: .isDirectory)
        guard
            let reference = try? String(
                contentsOf: repository.appending(path: "refs").appending(path: "main"), encoding: .utf8),
            case let commit = reference.trimmingCharacters(in: .whitespacesAndNewlines),
            isCommitHash(commit)
        else { return nil }
        let snapshot = repository.appending(path: "snapshots").appending(
            path: commit, directoryHint: .isDirectory)
        guard requiredFiles.allSatisfy({ (size(of: snapshot.appending(path: $0)) ?? 0) > 0 }),
            let weights = weightFiles(in: snapshot)
        else { return nil }
        let sizes = weights.map { wholeSize(of: snapshot.appending(path: $0)) }
        guard !sizes.contains(nil), sizes.compactMap(\.self).reduce(0, +) >= minimumWeightBytes else {
            return nil
        }
        return snapshot
    }

    /// Whether `text` is a full commit hash, the only name a snapshot directory is given.
    static func isCommitHash(_ text: String) -> Bool {
        text.count == 40 && text.allSatisfy(\.isHexDigit)
    }

    /// The weight files in `snapshot`, or nil when there are none or a numbered shard is missing.
    static func weightFiles(in snapshot: URL) -> [String]? {
        guard let listed = try? FileManager.default.contentsOfDirectory(atPath: snapshot.path) else {
            return nil
        }
        let weights = listed.filter { $0.hasSuffix(".safetensors") }.sorted()
        guard !weights.isEmpty else { return nil }
        for name in weights {
            // A shard such as `model-00001-of-00002.safetensors` needs every sibling its count names.
            guard let match = name.wholeMatch(of: /(.+)-\d+-of-(\d+)\.safetensors/), let count = Int(match.2)
            else { continue }
            let width = match.2.count
            for number in 1...max(1, count) {
                let digits = String(number)
                let padded = String(repeating: "0", count: max(0, width - digits.count)) + digits
                guard listed.contains("\(match.1)-\(padded)-of-\(match.2).safetensors") else { return nil }
            }
        }
        return weights
    }

    /// A safetensors file's length when it matches its own header, which a cut-off download never does.
    static func wholeSize(of file: URL) -> UInt64? {
        guard let length = size(of: file), length > 8,
            let handle = try? FileHandle(forReadingFrom: file.resolvingSymlinksInPath())
        else { return nil }
        defer { try? handle.close() }
        guard let prefix = try? handle.read(upToCount: 8), prefix.count == 8 else { return nil }
        let headerLength = prefix.enumerated().reduce(UInt64(0)) {
            $0 | UInt64($1.element) << (8 * $1.offset)
        }
        guard headerLength > 0, headerLength <= largestHeader, 8 + headerLength <= length,
            let header = try? handle.read(upToCount: Int(headerLength)), header.count == Int(headerLength),
            let tensors = try? JSONSerialization.jsonObject(with: header) as? [String: Any]
        else { return nil }
        let end =
            tensors.values.compactMap { ($0 as? [String: Any])?["data_offsets"] as? [UInt64] }
            .compactMap(\.last).max() ?? 0
        return length == 8 + headerLength + end ? length : nil
    }

    /// The byte length of the regular file `url` names, through any symbolic link.
    static func size(of url: URL) -> UInt64? {
        let values = try? url.resolvingSymlinksInPath().resourceValues(forKeys: [
            .fileSizeKey, .isRegularFileKey,
        ])
        guard values?.isRegularFile == true, let size = values?.fileSize else { return nil }
        return UInt64(size)
    }
}

extension LocalModel {
    /// The least cached weights may weigh to be believed whole: nine tenths of the recorded download.
    var minimumWeightBytes: UInt64 { UInt64(max(0, downloadBytes)) / 10 * 9 }

    /// Where the weights load from: the cache's copy when whole, otherwise what `downloader` fetches.
    func weightsDirectory(
        cache: URL, downloader: @Sendable () -> any MLXLMCommon.Downloader,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        if let snapshot = CachedSnapshot.complete(
            identifier: identifier, in: cache, minimumWeightBytes: minimumWeightBytes)
        {
            onProgress(1)
            return snapshot
        }
        let resolved = try await resolve(
            configuration: ModelConfiguration(id: identifier), from: downloader(), useLatest: false,
            progressHandler: { onProgress($0.fractionCompleted) })
        return resolved.modelDirectory
    }
}
