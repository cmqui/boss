// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "bossctl",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(
            name: "bossctl",
            targets: ["bossctl"]
        ),
    ],
    dependencies: [
        .package(path: "../libboss-apple"),
    ],
    targets: [
        .executableTarget(
            name: "bossctl",
            dependencies: [
                .product(name: "libbossApple", package: "libboss-apple"),
            ]
        ),
        .testTarget(
            name: "bossctlTests",
            dependencies: ["bossctl"]
        ),
    ]
)
