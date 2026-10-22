// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TypeSafe",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .tvOS(.v16),
        .watchOS(.v9),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "TypeSafe", targets: ["TypeSafe"]),
        .executable(name: "TypeSafeDemo", targets: ["TypeSafeDemo"]),
    ],
    targets: [
        // Linux toolchains have no zlib module, so the package declares its own.
        .systemLibrary(name: "CZlib", path: "Sources/CZlib"),
        .target(name: "TypeSafe", dependencies: ["CZlib"]),
        .executableTarget(
            name: "TypeSafeDemo",
            dependencies: ["TypeSafe"],
            path: "Examples/Demo"
        ),
        .testTarget(name: "TypeSafeTests", dependencies: ["TypeSafe", "CZlib"]),
        .testTarget(
            name: "TypeSafeIntegrationTests",
            dependencies: ["TypeSafe"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
