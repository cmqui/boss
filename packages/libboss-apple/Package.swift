// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "libboss-apple",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "libbossApple",
            targets: ["libbossApple"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "CBossRustFFI",
            publicHeadersPath: "include"
        ),
        .target(
            name: "libbossApple",
            dependencies: [
                "CBossRustFFI",
            ]
        ),
        .testTarget(
            name: "libbossAppleTests",
            dependencies: ["libbossApple"]
        ),
    ]
)
