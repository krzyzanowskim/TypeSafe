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
    ],
    targets: [
        .target(name: "TypeSafe"),
        .testTarget(name: "TypeSafeTests", dependencies: ["TypeSafe"]),
    ]
)
