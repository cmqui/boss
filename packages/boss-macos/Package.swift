// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "boss-macos",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(
            name: "boss-macos",
            targets: ["BossMacOS"]
        ),
    ],
    dependencies: [
        .package(path: "../libboss"),
        .package(path: "../libboss-apple"),
    ],
    targets: [
        .executableTarget(
            name: "BossMacOS",
            dependencies: [
                .product(name: "libboss", package: "libboss"),
                .product(name: "libbossApple", package: "libboss-apple"),
            ]
        ),
    ]
)
