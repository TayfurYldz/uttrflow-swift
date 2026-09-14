import Foundation
import MLX
import Testing

@testable import UttrflowLocalModel

/// A safetensors file holding only a header naming these tensors, each an empty `U8` or its given type.
private func safetensors(_ tensors: [String: String]) -> Data {
    let entries = tensors.sorted { $0.key < $1.key }.map {
        #""\#($0.key)":{"dtype":"\#($0.value)","shape":[0],"data_offsets":[0,0]}"#
    }
    let header = Data(
        ("{" + (entries + [#""__metadata__":{"format":"mlx"}"#]).joined(separator: ",") + "}").utf8)
    var length = UInt64(header.count).littleEndian
    var file = Data(bytes: &length, count: 8)
    file.append(header)
    file.append(Data([0]))
    return file
}

@Suite("Which layers load quantized, read from the weights on disk")
struct QuantizedLayerPlanTests {
    @Test("A layer with scales on disk is quantized, under the language model's prefix or not")
    func quantizedLayersAreFound() throws {
        let cache = try FakeCache()
        try cache.add(
            "model-00001-of-00002.safetensors",
            safetensors([
                "language_model.model.layers.0.self_attn.q_proj.weight": "U32",
                "language_model.model.layers.0.self_attn.q_proj.scales": "BF16",
                "language_model.model.layers.0.self_attn.q_proj.biases": "BF16",
                "language_model.model.layers.0.input_layernorm.weight": "BF16",
            ]))
        try cache.add(
            "model-00002-of-00002.safetensors",
            safetensors([
                "model.layers.1.mlp.up_proj.weight": "U32", "model.layers.1.mlp.up_proj.scales": "F16",
            ]))
        let plan = try #require(QuantizedLayerPlan.read(in: cache.snapshot))

        #expect(plan.source(of: "model.layers.0.self_attn.q_proj") == "model.layers.0.self_attn.q_proj")
        #expect(plan.hasBiases("model.layers.0.self_attn.q_proj"))
        #expect(plan.scalesType("model.layers.0.self_attn.q_proj") == "BF16")
        #expect(plan.scalesType("model.layers.1.mlp.up_proj") == "F16")
        #expect(!plan.hasBiases("model.layers.1.mlp.up_proj"))
        #expect(plan.source(of: "model.layers.0.input_layernorm") == nil)
        #expect(plan.scalesType("model.layers.0.input_layernorm") == nil)
        #expect(!plan.hasBiases("model.layers.0.input_layernorm"))
    }

    @Test(
        "An output head tied to the embedding takes the embedding's quantization, and only when it has none of its own"
    )
    func tiedHeadFollowsTheEmbedding() throws {
        let tied = QuantizedLayerPlan(dtypes: [
            "model.embed_tokens.weight": "U32", "model.embed_tokens.scales": "BF16",
            "model.embed_tokens.biases": "BF16",
        ])
        #expect(tied.source(of: "lm_head") == "model.embed_tokens")
        #expect(tied.hasBiases("lm_head"))

        let untied = QuantizedLayerPlan(dtypes: [
            "lm_head.weight": "BF16", "model.embed_tokens.scales": "BF16",
        ])
        #expect(untied.source(of: "lm_head") == nil)
    }

    @Test("A directory with no weights, or a header that cannot be read, gives no plan")
    func unreadableGivesNothing() throws {
        let empty = try FakeCache()
        #expect(QuantizedLayerPlan.read(in: empty.snapshot) == nil)

        let broken = try FakeCache()
        try broken.add("model.safetensors", Data("not a header".utf8))
        #expect(QuantizedLayerPlan.read(in: broken.snapshot) == nil)

        let missing = empty.root.appending(path: "nowhere")
        #expect(QuantizedLayerPlan.read(in: missing) == nil)
    }

    @Test("Scales stored as a floating type map to MLX's, and any other type builds no placeholder")
    func scalesTypes() {
        #expect(QuantizedLayerPlan.scalesDType(named: "F16") == .float16)
        #expect(QuantizedLayerPlan.scalesDType(named: "BF16") == .bfloat16)
        #expect(QuantizedLayerPlan.scalesDType(named: "F32") == .float32)
        #expect(QuantizedLayerPlan.scalesDType(named: "U32") == nil)
    }

    @Test("A placeholder is as wide as the packed weight and as many groups as the scales")
    func placeholderShapes() {
        let shapes = QuantizedLayerPlan.shapes(rows: 2_048, columns: 2_560, groupSize: 64, bits: 4)
        #expect(shapes.weight == [2_048, 320])
        #expect(shapes.scales == [2_048, 40])
    }
}
