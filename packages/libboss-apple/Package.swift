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
        .executable(
            name: "boss-bootstrap",
            targets: ["boss-bootstrap"]
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
        .executableTarget(
            name: "boss-bootstrap",
            dependencies: [
                "libbossApple",
            ]
        ),
        .testTarget(
            name: "libbossAppleTests",
            dependencies: ["libbossApple"]
        ),
    ]
)
