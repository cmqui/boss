// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "boss-apple-app",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "bossAppleApp",
            targets: ["BossAppleApp"]
        ),
    ],
    dependencies: [
        .package(path: "../../../core/libboss-apple"),
    ],
    targets: [
        .target(
            name: "BossAppleApp",
            dependencies: [
                .product(name: "libbossApple", package: "libboss-apple"),
            ]
        ),
        .testTarget(
            name: "BossAppleAppTests",
            dependencies: ["BossAppleApp"]
        ),
    ]
)
