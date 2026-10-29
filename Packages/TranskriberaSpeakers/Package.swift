// swift-tools-version: 5.9
// Talaridentifiering med pyannote community-1 (via FluidAudio), i ett eget paket så att
// den kan testas mot riktiga modeller med `swift test`.

import PackageDescription

let package = Package(
    name: "TranskriberaSpeakers",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TranskriberaSpeakers", targets: ["TranskriberaSpeakers"])
    ],
    dependencies: [
        .package(path: "../TranskriberaCore"),
        // Exakt samma versioner som är låsta i Package.resolved, så att testet kör de
        // bibliotek som följer med appen. Ändra alla samtidigt.
        .package(url: "https://github.com/FluidInference/FluidAudio", exact: "0.17.7"),
        // Bara för testet som jämför med dagens talaridentifiering (SpeakerKit).
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift", exact: "1.1.1")
    ],
    targets: [
        .target(
            name: "TranskriberaSpeakers",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "TranskriberaCore", package: "TranskriberaCore")
            ]
        ),
        .testTarget(
            name: "TranskriberaSpeakersTests",
            dependencies: [
                "TranskriberaSpeakers",
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "TranskriberaCore", package: "TranskriberaCore"),
                .product(name: "SpeakerKit", package: "argmax-oss-swift")
            ]
        )
    ]
)
