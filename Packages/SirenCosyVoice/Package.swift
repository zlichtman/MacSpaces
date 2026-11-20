// swift-tools-version: 5.10
// CosyVoice 3 for Siren, vendored from soniqo/speech-swift (Apache-2.0); see NOTICE.
// That package can't be a dependency: it pins mlx-swift below 0.32, and
// mlx-audio-swift needs 0.32.3 or later. These three targets build on 0.32.
import PackageDescription

let package = Package(
    name: "SirenCosyVoice",
    platforms: [.macOS("15.0")],
    products: [
        .library(name: "CosyVoiceTTS", targets: ["CosyVoiceTTS"]),
    ],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift.git", .upToNextMajor(from: "0.32.3")),
        .package(url: "https://github.com/huggingface/swift-transformers.git", .upToNextMajor(from: "1.1.6")),
    ],
    targets: [
        .target(name: "AudioCommon", dependencies: [
            .product(name: "Hub", package: "swift-transformers"),
        ]),
        .target(name: "MLXCommon", dependencies: [
            "AudioCommon",
            .product(name: "MLX", package: "mlx-swift"),
            .product(name: "MLXNN", package: "mlx-swift"),
            .product(name: "MLXFast", package: "mlx-swift"),
            .product(name: "MLXFFT", package: "mlx-swift"),
        ]),
        .target(name: "CosyVoiceTTS", dependencies: [
            "AudioCommon",
            "MLXCommon",
            .product(name: "MLX", package: "mlx-swift"),
            .product(name: "MLXNN", package: "mlx-swift"),
            .product(name: "MLXFast", package: "mlx-swift"),
        ]),
    ]
)
