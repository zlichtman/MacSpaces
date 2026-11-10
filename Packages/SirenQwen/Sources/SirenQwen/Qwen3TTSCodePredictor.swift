// Apple silicon only: MLX voices never run on Intel, where this builds empty (Float16 and Metal).
#if arch(arm64)
import Foundation
@preconcurrency import MLX
@preconcurrency import MLXAudioCore
import MLXNN

// MARK: - Code Predictor Attention

private let compiledCodePredictorSwiGLU: @Sendable (MLXArray, MLXArray) -> MLXArray = {
    MLX.compile(shapeless: true) { gate, up in
        silu(gate) * up
    }
}()

final class CodePredictorAttention: Module {
    let numHeads: Int
    let numKvHeads: Int
    let headDim: Int
    let scale: Float
    let ropeBase: Float

    @ModuleInfo(key: "q_proj") var qProj: Linear
    @ModuleInfo(key: "k_proj") var kProj: Linear
    @ModuleInfo(key: "v_proj") var vProj: Linear
    @ModuleInfo(key: "o_proj") var oProj: Linear
    @ModuleInfo(key: "q_norm") var qNorm: RMSNorm
    @ModuleInfo(key: "k_norm") var kNorm: RMSNorm

    init(config: Qwen3TTSTalkerCodePredictorConfig, layerIdx: Int) {
        self.numHeads = config.numAttentionHeads
        self.numKvHeads = config.numKeyValueHeads
        self.headDim = config.headDim
        self.scale = 1.0 / Foundation.sqrt(Float(headDim))
        self.ropeBase = config.ropeTheta

        _qProj.wrappedValue = Linear(config.hiddenSize, numHeads * headDim, bias: config.attentionBias)
        _kProj.wrappedValue = Linear(config.hiddenSize, numKvHeads * headDim, bias: config.attentionBias)
        _vProj.wrappedValue = Linear(config.hiddenSize, numKvHeads * headDim, bias: config.attentionBias)
        _oProj.wrappedValue = Linear(numHeads * headDim, config.hiddenSize, bias: config.attentionBias)
        _qNorm.wrappedValue = RMSNorm(dimensions: headDim, eps: config.rmsNormEps)
        _kNorm.wrappedValue = RMSNorm(dimensions: headDim, eps: config.rmsNormEps)
    }

    func callAsFunction(
        _ x: MLXArray,
        offset: Int,
        mask: MLXArray? = nil,
        cache: (any KVCache)? = nil
    ) -> MLXArray {
        let (batch, seqLen, _) = (x.dim(0), x.dim(1), x.dim(2))

        var q = qProj(x).reshaped(batch, seqLen, numHeads, headDim)
        var k = kProj(x).reshaped(batch, seqLen, numKvHeads, headDim)
        var v = vProj(x).reshaped(batch, seqLen, numKvHeads, headDim)

        q = qNorm(q)
        k = kNorm(k)

        q = q.transposed(0, 2, 1, 3)
        k = k.transposed(0, 2, 1, 3)
        v = v.transposed(0, 2, 1, 3)

        // Fused RoPE (from Vocello): one kernel per tensor instead of the
        // rotate-half chain. Generation here is bound by building graphs and
        // launching kernels, so fewer ops is directly less time.
        // `traditional: false` is the rotate-half layout.
        q = MLXFast.RoPE(q, dimensions: headDim, traditional: false, base: ropeBase, scale: 1.0, offset: offset)
        k = MLXFast.RoPE(k, dimensions: headDim, traditional: false, base: ropeBase, scale: 1.0, offset: offset)

        if let cache {
            (k, v) = cache.update(keys: k, values: v)
        }

        let output = MLXFast.scaledDotProductAttention(
            queries: q, keys: k, values: v, scale: scale, mask: mask
        )
        return oProj(output.transposed(0, 2, 1, 3).reshaped(batch, seqLen, -1))
    }
}

// MARK: - Code Predictor MLP

final class CodePredictorMLP: Module {
    @ModuleInfo(key: "gate_proj") var gateProj: Linear
    @ModuleInfo(key: "up_proj") var upProj: Linear
    @ModuleInfo(key: "down_proj") var downProj: Linear

    init(config: Qwen3TTSTalkerCodePredictorConfig) {
        _gateProj.wrappedValue = Linear(config.hiddenSize, config.intermediateSize, bias: false)
        _upProj.wrappedValue = Linear(config.hiddenSize, config.intermediateSize, bias: false)
        _downProj.wrappedValue = Linear(config.intermediateSize, config.hiddenSize, bias: false)
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        downProj(compiledCodePredictorSwiGLU(gateProj(x), upProj(x)))
    }
}

// MARK: - Code Predictor Decoder Layer

final class CodePredictorDecoderLayer: Module {
    @ModuleInfo(key: "self_attn") var selfAttn: CodePredictorAttention
    @ModuleInfo var mlp: CodePredictorMLP
    @ModuleInfo(key: "input_layernorm") var inputLayernorm: RMSNorm
    @ModuleInfo(key: "post_attention_layernorm") var postAttentionLayernorm: RMSNorm

    init(config: Qwen3TTSTalkerCodePredictorConfig, layerIdx: Int) {
        _selfAttn.wrappedValue = CodePredictorAttention(config: config, layerIdx: layerIdx)
        _mlp.wrappedValue = CodePredictorMLP(config: config)
        _inputLayernorm.wrappedValue = RMSNorm(dimensions: config.hiddenSize, eps: config.rmsNormEps)
        _postAttentionLayernorm.wrappedValue = RMSNorm(dimensions: config.hiddenSize, eps: config.rmsNormEps)
    }

    func callAsFunction(
        _ x: MLXArray,
        offset: Int,
        mask: MLXArray? = nil,
        cache: (any KVCache)? = nil
    ) -> MLXArray {
        var out = x + selfAttn(inputLayernorm(x), offset: offset, mask: mask, cache: cache)
        out = out + mlp(postAttentionLayernorm(out))
        return out
    }
}

// MARK: - Code Predictor Step Constants

/// What one generation's code predictor reuses from frame to frame (from
/// Vocello): its cache is trimmed to the start before every frame, so each
/// frame replays the same positions and the same 2-token mask.
final class CodePredictorStepConstants {
    private var causalMasks: [Int: MLXArray] = [:]
    private var compiledPlan: CodePredictorCompiledPlan?

    fileprivate func causalMask(seqLen: Int, compute: () -> MLXArray) -> MLXArray {
        if let cached = causalMasks[seqLen] { return cached }
        let fresh = compute()
        causalMasks[seqLen] = fresh
        return fresh
    }

    /// Traced on the first frame and replayed for the rest of the generation.
    func compiledPlan(for predictor: Qwen3TTSCodePredictor, dtype: DType) -> CodePredictorCompiledPlan {
        if let compiledPlan { return compiledPlan }
        let fresh = CodePredictorCompiledPlan(predictor: predictor, dtype: dtype)
        compiledPlan = fresh
        return fresh
    }
}

// MARK: - Code Predictor Model (inner)

final class CodePredictorModel: Module {
    let config: Qwen3TTSTalkerCodePredictorConfig
    @ModuleInfo(key: "codec_embedding") var codecEmbedding: [Embedding]
    let layers: [CodePredictorDecoderLayer]
    @ModuleInfo var norm: RMSNorm

    init(config: Qwen3TTSTalkerCodePredictorConfig, talkerHiddenSize: Int) {
        self.config = config
        _codecEmbedding.wrappedValue = (0 ..< config.numCodeGroups - 1).map { _ in
            Embedding(embeddingCount: config.vocabSize, dimensions: talkerHiddenSize)
        }
        self.layers = (0 ..< config.numHiddenLayers).map { CodePredictorDecoderLayer(config: config, layerIdx: $0) }
        _norm.wrappedValue = RMSNorm(dimensions: config.hiddenSize, eps: config.rmsNormEps)
    }

    func callAsFunction(
        _ inputsEmbeds: MLXArray,
        mask: MLXArray? = nil,
        cache: [any KVCache]? = nil,
        stepConstants: CodePredictorStepConstants? = nil
    ) -> MLXArray {
        let seqLen = inputsEmbeds.dim(1)

        let offset: Int = if let firstCache = cache?.first {
            firstCache.offset
        } else {
            0
        }

        // Positions always run on from the cache's offset; RoPE is applied
        // inside the attention.
        var causalMask = mask
        if causalMask == nil, seqLen > 1 {
            let compute = { MultiHeadAttention.createAdditiveCausalMask(seqLen).asType(inputsEmbeds.dtype) }
            causalMask = stepConstants?.causalMask(seqLen: seqLen, compute: compute) ?? compute()
        }

        var x = inputsEmbeds
        for (i, layer) in layers.enumerated() {
            x = layer(x, offset: offset, mask: causalMask, cache: cache?[i])
        }
        return norm(x)
    }

    func makeCache() -> [any KVCache] {
        layers.map { _ in KVCacheSimple() }
    }
}

// MARK: - Code Predictor (public)

final class Qwen3TTSCodePredictor: Module {
    let config: Qwen3TTSTalkerCodePredictorConfig
    let numCodeGroups: Int
    let talkerHiddenSize: Int

    @ModuleInfo(key: "small_to_mtp_projection") var projection: Linear?
    @ModuleInfo var model: CodePredictorModel
    @ModuleInfo(key: "lm_head") var lmHead: [Linear]

    var codecEmbedding: [Embedding] { model.codecEmbedding }

    init(config: Qwen3TTSTalkerCodePredictorConfig, talkerHiddenSize: Int) {
        self.config = config
        self.numCodeGroups = config.numCodeGroups
        self.talkerHiddenSize = talkerHiddenSize

        if config.hiddenSize != talkerHiddenSize {
            _projection.wrappedValue = Linear(talkerHiddenSize, config.hiddenSize, bias: true)
        } else {
            _projection.wrappedValue = nil
        }

        _model.wrappedValue = CodePredictorModel(config: config, talkerHiddenSize: talkerHiddenSize)
        _lmHead.wrappedValue = (0 ..< config.numCodeGroups - 1).map { _ in
            Linear(config.hiddenSize, config.vocabSize, bias: false)
        }
    }

    func callAsFunction(
        _ inputsEmbeds: MLXArray,
        mask: MLXArray? = nil,
        cache: [any KVCache]? = nil,
        generationStep: Int = 0,
        stepConstants: CodePredictorStepConstants? = nil
    ) -> (MLXArray, [any KVCache]?, Int) {
        var embeds = inputsEmbeds
        if let proj = projection {
            embeds = proj(embeds)
        }

        let x = model(embeds, mask: mask, cache: cache, stepConstants: stepConstants)
        let logits = lmHead[generationStep](x)
        return (logits, cache, generationStep + 1)
    }

    func makeCache() -> [any KVCache] {
        model.makeCache()
    }
}
#endif
