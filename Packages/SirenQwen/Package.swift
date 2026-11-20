// swift-tools-version: 6.0
// Qwen3-TTS for Siren, vendored from mlx-audio-swift (MIT) with speed-ups
// ported from Vocello (MIT); see NOTICE. Its own module, so Vocello-style
// changes don't need a fork of mlx-audio-swift, which Siren still uses for
// everything else.
import PackageDescription

let package = Package(
    name: "SirenQwen",
    platforms: [.macOS("15.0")],
    products: [
        .library(name: "SirenQwen", targets: ["SirenQwen"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Blaizzy/mlx-audio-swift.git", revision: "d8e2cafea891928075d3c8577b1a05b99396594e"),
        .package(url: "https://github.com/ml-explore/mlx-swift.git", .upToNextMajor(from: "0.32.3")),
        .package(url: "https://github.com/huggingface/swift-transformers.git", .upToNextMajor(from: "1.1.6")),
        .package(url: "https://github.com/huggingface/swift-huggingface.git", .upToNextMajor(from: "0.8.1")),
    ],
    targets: [
        .target(name: "SirenQwen", dependencies: [
            .product(name: "MLXAudioCore", package: "mlx-audio-swift"),
            .product(name: "MLXAudioCodecs", package: "mlx-audio-swift"),
            .product(name: "MLXAudioTTS", package: "mlx-audio-swift"),
            .product(name: "MLX", package: "mlx-swift"),
            .product(name: "MLXFast", package: "mlx-swift"),
            .product(name: "MLXNN", package: "mlx-swift"),
            .product(name: "MLXRandom", package: "mlx-swift"),
            .product(name: "Tokenizers", package: "swift-transformers"),
            .product(name: "HuggingFace", package: "swift-huggingface"),
        ]),
    ]
)
