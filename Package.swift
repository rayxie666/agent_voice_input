// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "VoiceInput",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "VoiceInput", targets: ["VoiceInput"])
    ],
    targets: [
        .target(
            name: "CWhisper",
            path: "Sources/CWhisper",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "VoiceInput",
            dependencies: ["CWhisper"],
            path: "Sources/VoiceInput",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Carbon"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("Accelerate"),
                .linkedFramework("CoreML"),
                .unsafeFlags([
                    "-Lvendor/whisper.cpp/build/src",
                    "-Lvendor/whisper.cpp/build/ggml/src",
                    "-Lvendor/whisper.cpp/build/ggml/src/ggml-metal",
                    "-Lvendor/whisper.cpp/build/ggml/src/ggml-blas",
                    "-Lvendor/whisper.cpp/build/ggml/src/ggml-cpu",
                    "-lwhisper",
                    "-lggml",
                    "-lggml-base",
                    "-lggml-cpu",
                    "-lggml-metal",
                    "-lggml-blas",
                    "-lc++",
                ]),
            ]
        ),
    ]
)
