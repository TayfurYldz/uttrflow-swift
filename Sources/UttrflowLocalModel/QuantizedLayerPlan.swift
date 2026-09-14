// Decides which layers are built quantized from the weights on disk, before the weights are read.
import Foundation

/// The quantized layers a snapshot holds, read from its safetensors headers. See `Docs/performance.md`.
struct QuantizedLayerPlan: Sendable, Equatable {
    /// The prefix a vision-language conversion puts before the language model's weights.
    static let languageModelPrefix = "language_model."

    /// Every tensor's element type, by the name the model's own parameter paths use.
    let dtypes: [String: String]

    /// Reads the tensor names and element types from every safetensors header in `directory`.
    static func read(in directory: URL) -> QuantizedLayerPlan? {
        guard
            let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
                .filter({ $0.hasSuffix(".safetensors") }), !names.isEmpty
        else { return nil }
        var dtypes: [String: String] = [:]
        for name in names {
            guard let header = CachedSnapshot.header(of: directory.appending(path: name)) else { return nil }
            for (tensor, entry) in header {
                guard let dtype = (entry as? [String: Any])?["dtype"] as? String else { continue }
                let key =
                    tensor.hasPrefix(languageModelPrefix)
                    ? String(tensor.dropFirst(languageModelPrefix.count)) : tensor
                dtypes[key] = dtype
            }
        }
        return QuantizedLayerPlan(dtypes: dtypes)
    }

    /// The layer whose weights on disk stand for `path`: its own, or the embedding a tied output head copies.
    func source(of path: String) -> String? {
        if dtypes["\(path).scales"] != nil { return path }
        if path == "lm_head", dtypes["lm_head.weight"] == nil, dtypes["model.embed_tokens.scales"] != nil {
            return "model.embed_tokens"
        }
        return nil
    }

    /// Whether the layer at `path` is stored quantized with a zero point beside its scales.
    func hasBiases(_ path: String) -> Bool {
        source(of: path).map { dtypes["\($0).biases"] != nil } ?? false
    }

    /// The element type of the layer's scales, which its placeholder must share.
    func scalesType(_ path: String) -> String? {
        source(of: path).flatMap { dtypes["\($0).scales"] }
    }

    /// The shapes of a placeholder quantized weight and its scales for a `rows` by `columns` layer.
    static func shapes(rows: Int, columns: Int, groupSize: Int, bits: Int) -> (weight: [Int], scales: [Int]) {
        ([rows, columns * bits / 32], [rows, columns / groupSize])
    }
}
