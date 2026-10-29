// swift-tools-version: 5.9
// Det tunna lagret mellan appen och WhisperKit som kan testas mot en riktig modell
// med `swift test`: förlopp och löpande text medan Whisper transkriberar.

import PackageDescription

let package = Package(
    name: "TranskriberaWhisper",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TranskriberaWhisper", targets: ["TranskriberaWhisper"])
    ],
    dependencies: [
        // Exakt samma version som är låst i Package.resolved, så att testet kör den
        // WhisperKit som följer med appen. Ändra båda samtidigt.
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift", exact: "1.1.1")
    ],
    targets: [
        .target(
            name: "TranskriberaWhisper",
            dependencies: [.product(name: "WhisperKit", package: "argmax-oss-swift")]
        ),
        .testTarget(name: "TranskriberaWhisperTests", dependencies: ["TranskriberaWhisper"])
    ]
)
