// Loads a quantized model without quantizing a random matrix for every layer first.
import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import MLXNN

/// Builds each quantized layer from placeholders shaped like the weights on disk, so loading leaves no MLX graph behind. See `Docs/performance.md`.
enum QuantizedLoad {
    /// The model in `directory` in a container, its quantized layers built before the weights replace their placeholders.
    static func container(
        from directory: URL, using tokenizerLoader: any TokenizerLoader
    ) async throws -> ModelContainer {
        let configuration = try Data(contentsOf: directory.appending(component: "config.json"))
        let base = try JSONDecoder.json5().decode(BaseConfiguration.self, from: configuration)
        let model = try await LLMTypeRegistry.shared.createModel(
            configuration: configuration, modelType: base.modelType)
        if let plan = QuantizedLayerPlan.read(in: directory), let quantization = base.perLayerQuantization {
            build(model, from: plan, quantization: quantization)
        }
        // Evaluates the global random key, cutting the chain of lazy splits the random initial weights left on it.
        eval(MLXRandom.globalState)
        let built = BuiltModel(model)
        let registry = ModelTypeRegistry<LanguageModel>(creators: [base.modelType: { _ in built.model }])
        return try await LLMModelFactory(typeRegistry: registry, modelRegistry: LLMRegistry.shared)
            .loadContainer(from: directory, using: tokenizerLoader)
    }

    /// Swaps every linear layer stored quantized for a quantized layer of unevaluated zeros, which the weights then replace.
    private static func build(
        _ model: Module, from plan: QuantizedLayerPlan, quantization: BaseConfiguration.PerLayerQuantization
    ) {
        var layers: [(String, Module)] = []
        for (path, module) in model.leafModules().flattened() {
            guard let linear = module as? Linear, !(module is Quantized),
                let (groupSize, bits, mode) = quantization.quantization(layer: path)?.asTuple,
                let scalesType = plan.scalesType(path).flatMap(QuantizedLayerPlan.scalesDType)
            else { continue }
            let (rows, columns) = linear.weight.shape2
            let shapes = QuantizedLayerPlan.shapes(
                rows: rows, columns: columns, groupSize: groupSize, bits: bits)
            layers.append(
                (
                    path,
                    QuantizedLinear(
                        weight: MLXArray.zeros(shapes.weight, dtype: .uint32),
                        bias: linear.bias.map { MLXArray.zeros($0.shape, dtype: $0.dtype) },
                        scales: MLXArray.zeros(shapes.scales, dtype: scalesType),
                        biases: plan.hasBiases(path) ? MLXArray.zeros(shapes.scales, dtype: scalesType) : nil,
                        groupSize: groupSize, bits: bits, mode: mode)
                ))
        }
        model.update(modules: ModuleChildren.unflattened(layers))
    }
}

/// The one model instance the factory is handed, built before the factory runs.
private final class BuiltModel: @unchecked Sendable {
    // Read once, by the factory's single call to its creator.
    let model: LanguageModel

    init(_ model: LanguageModel) { self.model = model }
}
