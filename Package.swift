// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "conure",
    platforms: [.macOS("15.0")],
    products: [
        .library(name: "ConureCore", targets: ["ConureCore"]),
        .executable(name: "conure", targets: ["conure"]),
    ],
    dependencies: [
        .package(path: "vendor/speech-swift"),
        .package(url: "https://github.com/FluidInference/FluidAudio", exact: "0.17.4"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "ConureCore",
            dependencies: [
                .product(name: "ParakeetASR", package: "speech-swift"),
                .product(name: "SpeechVAD", package: "speech-swift"),
                .product(name: "AudioCommon", package: "speech-swift"),
                .product(name: "FluidAudio", package: "FluidAudio"),
            ]
        ),
        .executableTarget(
            name: "conure",
            dependencies: [
                "ConureCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .executableTarget(
            name: "ConureApp",
            path: "App/Sources/ConureApp"
        ),
        .testTarget(
            name: "ConureCoreTests",
            dependencies: ["ConureCore"],
            path: "Tests/ConureCoreTests"
        ),
    ]
)
