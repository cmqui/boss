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
        .package(path: "../libboss-apple"),
    ],
    targets: [
        .executableTarget(
            name: "Boss",
            dependencies: [
                .product(name: "libbossApple", package: "libboss-apple"),
            ],
            path: "Sources/BossMacOS",
            resources: [
                .process("Resources"),
            ]
        ),
    ]
)
