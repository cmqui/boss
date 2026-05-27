// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "boss-macos",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(
            name: "Boss",
            targets: ["Boss"]
        ),
    ],
    dependencies: [
        .package(path: "../app-core"),
        .package(path: "../../../core/libboss-apple"),
    ],
    targets: [
        .executableTarget(
            name: "Boss",
            dependencies: [
                .product(name: "bossAppleApp", package: "boss-apple-app"),
                .product(name: "libbossApple", package: "libboss-apple"),
            ],
            path: "Sources/BossMacOS",
            resources: [
                .process("Resources"),
            ]
        ),
    ]
)
