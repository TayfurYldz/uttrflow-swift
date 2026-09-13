// Tests that a model already whole on disk loads without the hub, and that anything less still reaches it.

import Foundation
import MLXLMCommon
import Testing
import os

@testable import UttrflowLocalModel

/// A downloader that records every call and refuses it, standing in for the network.
private final class RefusingDownloader: MLXLMCommon.Downloader {
    private let calls = OSAllocatedUnfairLock(initialState: 0)

    /// How many times anything asked the hub for a snapshot.
    var count: Int { calls.withLock { $0 } }

    /// What the stand-in hub throws, so a test can tell it from a real failure.
    struct Refused: Error {}

    func download(
        id: String, revision: String?, matching patterns: [String], useLatest: Bool,
        progressHandler: @Sendable @escaping (Progress) -> Void
    ) async throws -> URL {
        calls.withLock { $0 += 1 }
        throw Refused()
    }
}

/// Every fraction a load reported, from whichever thread reported it.
private final class Fractions: Sendable {
    private let seen = OSAllocatedUnfairLock<[Double]>(initialState: [])

    var reported: [Double] { seen.withLock { $0 } }

    func record(_ fraction: Double) { seen.withLock { $0.append(fraction) } }
}

/// A Hugging Face cache laid out as the hub leaves it: blobs, a ref and a snapshot of links.
struct FakeCache {
    let root: URL
    let identifier = "example-org/tiny-model"
    let commit = String(repeating: "a1", count: 20)

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "cached-snapshot-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: snapshot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: blobs, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: repository.appending(path: "refs"), withIntermediateDirectories: true)
        try Data((commit + "\n").utf8).write(to: repository.appending(path: "refs/main"))
    }

    var repository: URL { root.appending(path: "models--example-org--tiny-model") }
    var blobs: URL { repository.appending(path: "blobs") }
    var snapshot: URL { repository.appending(path: "snapshots/\(commit)") }

    /// Writes `data` as a blob and links it into the snapshot under `name`, the way the hub does.
    func add(_ name: String, _ data: Data) throws {
        let blob = blobs.appending(path: UUID().uuidString)
        try data.write(to: blob)
        try FileManager.default.createSymbolicLink(
            atPath: snapshot.appending(path: name).path,
            withDestinationPath: "../../blobs/\(blob.lastPathComponent)")
    }

    /// Everything but the weights: the architecture and the tokenizer.
    func addConfiguration() throws {
        for name in CachedSnapshot.requiredFiles { try add(name, Data("{}".utf8)) }
    }

    /// A safetensors file whose header claims `bytes` of tensor data, cut to `keeping` of them.
    static func weights(bytes: Int, keeping: Int? = nil) -> Data {
        let header = Data(#"{"w":{"dtype":"U8","shape":[\#(bytes)],"data_offsets":[0,\#(bytes)]}}"#.utf8)
        var length = UInt64(header.count).littleEndian
        var file = Data(bytes: &length, count: 8)
        file.append(header)
        file.append(Data(repeating: 7, count: keeping ?? bytes))
        return file
    }

    /// The weights a whole snapshot is allowed to weigh no less than.
    static let minimum: UInt64 = 256

    func complete() -> URL? {
        CachedSnapshot.complete(identifier: identifier, in: root, minimumWeightBytes: Self.minimum)
    }

    func model() -> LocalModel { Self.model(identifier: identifier) }

    static func model(identifier: String, downloadBytes: Int64 = 256) -> LocalModel {
        LocalModel(
            identifier: identifier, family: "Tiny", version: "1", parameterBillions: 0.1,
            quantisation: .fourBit, downloadBytes: downloadBytes, isMultilingual: true)
    }
}

@Suite("A model whole on disk loads without the network")
struct CachedSnapshotTests {
    @Test("A whole cached model is loaded from its snapshot, and the hub is never asked")
    func wholeCacheNeverAsksTheHub() async throws {
        let cache = try FakeCache()
        try cache.addConfiguration()
        try cache.add("model.safetensors", FakeCache.weights(bytes: 256))
        let hub = RefusingDownloader()
        let fractions = Fractions()
        let directory = try await cache.model().weightsDirectory(
            cache: cache.root, downloader: { hub }, onProgress: fractions.record)
        #expect(hub.count == 0)
        #expect(directory.standardizedFileURL == cache.snapshot.standardizedFileURL)
        #expect(fractions.reported == [1])
    }

    @Test("A cache missing its tokenizer still goes to the hub, so a first download keeps working")
    func incompleteCacheAsksTheHub() async throws {
        let cache = try FakeCache()
        try cache.add("config.json", Data("{}".utf8))
        try cache.add("model.safetensors", FakeCache.weights(bytes: 256))
        let hub = RefusingDownloader()
        await #expect(throws: RefusingDownloader.Refused.self) {
            _ = try await cache.model().weightsDirectory(
                cache: cache.root, downloader: { hub }, onProgress: { _ in })
        }
        #expect(hub.count == 1)
    }

    @Test("An empty cache goes to the hub")
    func emptyCacheAsksTheHub() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "no-cache-\(UUID().uuidString)")
        let hub = RefusingDownloader()
        await #expect(throws: RefusingDownloader.Refused.self) {
            _ = try await FakeCache.model(identifier: "example-org/tiny-model").weightsDirectory(
                cache: root, downloader: { hub }, onProgress: { _ in })
        }
        #expect(hub.count == 1)
    }

    @Test("Weights cut short of what their header promises are not trusted")
    func truncatedWeightsAreNotWhole() throws {
        let cache = try FakeCache()
        try cache.addConfiguration()
        try cache.add("model.safetensors", FakeCache.weights(bytes: 256, keeping: 200))
        #expect(cache.complete() == nil)
    }

    @Test("Weights lighter than the model is known to weigh are not trusted")
    func lightWeightsAreNotWhole() throws {
        let cache = try FakeCache()
        try cache.addConfiguration()
        try cache.add("model.safetensors", FakeCache.weights(bytes: 16))
        #expect(cache.complete() == nil)
    }

    @Test("A split model missing one shard is not trusted, and one with every shard is")
    func everyShardIsNeeded() throws {
        let cache = try FakeCache()
        try cache.addConfiguration()
        try cache.add("model-00001-of-00002.safetensors", FakeCache.weights(bytes: 128))
        #expect(cache.complete() == nil)
        try cache.add("model-00002-of-00002.safetensors", FakeCache.weights(bytes: 128))
        #expect(cache.complete()?.standardizedFileURL == cache.snapshot.standardizedFileURL)
    }

    @Test("A snapshot with no weights at all is not trusted")
    func noWeightsIsNotWhole() throws {
        let cache = try FakeCache()
        try cache.addConfiguration()
        #expect(cache.complete() == nil)
    }

    @Test("A ref that names no commit is not followed")
    func badReferenceIsNotFollowed() throws {
        let cache = try FakeCache()
        try cache.addConfiguration()
        try cache.add("model.safetensors", FakeCache.weights(bytes: 256))
        try Data("main".utf8).write(to: cache.repository.appending(path: "refs/main"))
        #expect(cache.complete() == nil)
        try FileManager.default.removeItem(at: cache.repository.appending(path: "refs/main"))
        #expect(cache.complete() == nil)
    }

    @Test("A header that is absurdly long, not JSON, or longer than the file is not believed")
    func corruptHeadersAreNotBelieved() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "headers-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        func size(of bytes: [UInt8]) throws -> UInt64? {
            let file = root.appending(path: UUID().uuidString)
            try Data(bytes).write(to: file)
            return CachedSnapshot.wholeSize(of: file)
        }
        #expect(try size(of: [0xFF, 0xFF, 0xFF, 0xFF, 0, 0, 0, 0, 1, 2]) == nil)
        #expect(try size(of: [2, 0, 0, 0, 0, 0, 0, 0] + Array("no".utf8)) == nil)
        #expect(try size(of: [0, 0, 0, 0, 0, 0, 0, 0, 1]) == nil)
        #expect(try size(of: [1, 2, 3]) == nil)
        #expect(CachedSnapshot.wholeSize(of: root.appending(path: "absent")) == nil)
        #expect(CachedSnapshot.size(of: root) == nil)
    }

    @Test("Only a full forty-character hexadecimal name counts as a commit")
    func commitHashes() {
        #expect(CachedSnapshot.isCommitHash(String(repeating: "0f", count: 20)))
        #expect(!CachedSnapshot.isCommitHash("main"))
        #expect(!CachedSnapshot.isCommitHash(String(repeating: "zz", count: 20)))
    }

    @Test("A model's cached weights must reach nine tenths of its recorded download")
    func minimumIsNineTenths() {
        #expect(LocalModel.gemma3.minimumWeightBytes == 2_727_000_000)
        #expect(FakeCache.minimum > 0)
    }
}
