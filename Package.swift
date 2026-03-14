// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Axon",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "axon", targets: ["Axon"]),
        .library(name: "AxonCore", targets: ["AxonCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.5.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(url: "https://github.com/apple/swift-testing.git", from: "0.12.0"),
    ],
    targets: [
        .executableTarget(
            name: "Axon",
            dependencies: [
                "AxonCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Hummingbird", package: "hummingbird"),
            ]
        ),
        .target(
            name: "AxonCore",
            linkerSettings: [
                .linkedFramework("ApplicationServices"),
                .linkedFramework("AppKit"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("CoreGraphics"),
            ]
        ),
        .testTarget(
            name: "AxonCoreTests",
            dependencies: [
                "AxonCore",
                .product(name: "Testing", package: "swift-testing"),
            ]
        ),
    ]
)
