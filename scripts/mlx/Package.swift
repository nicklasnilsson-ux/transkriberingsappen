// swift-tools-version:6.2
// Test 2026-11-13: kan Klangs MLX-version av Pianissimo köras från Swift utan ombyggnad?
// Körs bara i CI (.github/workflows/mlx-test.yml), ingår inte i appen.
import PackageDescription

let package = Package(
    name: "mlx-pianissimo",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Låst till en commit: biblioteket har inga versioner.
        .package(url: "https://github.com/Blaizzy/mlx-audio-swift.git", revision: "cf095e05a8cbb5aaceac92aeee0b2061b59ad30e"),
    ],
    targets: [
        .executableTarget(
            name: "mlx-pianissimo",
            dependencies: [
                .product(name: "MLXAudioSTT", package: "mlx-audio-swift"),
                .product(name: "MLXAudioCore", package: "mlx-audio-swift"),
            ]
        ),
    ]
)
