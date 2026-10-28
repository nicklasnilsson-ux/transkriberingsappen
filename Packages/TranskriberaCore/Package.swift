// swift-tools-version: 5.9
// Plattformsoberoende kärnlogik (formatering, export, sökning) som kan
// testas med `swift test` även utan Xcode.

import PackageDescription

let package = Package(
    name: "TranskriberaCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TranskriberaCore", targets: ["TranskriberaCore"])
    ],
    targets: [
        .target(name: "TranskriberaCore"),
        .testTarget(name: "TranskriberaCoreTests", dependencies: ["TranskriberaCore"])
    ]
)
