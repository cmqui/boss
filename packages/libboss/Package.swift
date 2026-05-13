// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "libboss",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "libboss",
            targets: ["libboss"]
        ),
    ],
    targets: [
        .target(
            name: "libboss"
        ),
        .testTarget(
            name: "libbossTests",
            dependencies: ["libboss"]
        ),
    ]
)
