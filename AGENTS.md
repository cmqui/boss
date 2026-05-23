Packages:
- `packages/libboss`: platform-agnostic BMAP protocol/core logic. Product: `libboss`.
- `packages/libboss-apple`: Apple/CoreBluetooth integration and async APIs over `libboss`. Product: `libbossApple`. Has tests in `Tests/libbossAppleTests`.
- `packages/bossctl`: macOS CLI for controlling devices through `libbossApple`. Product: `bossctl`.
- `packages/boss-apple-app`: apple-specific shared app logic. Product: `bossAppleApp`.
- `packages/boss-macos`: macOS SwiftUI app using `libbossApple`.
- `packages/boss-ios`: iOS SwiftUI app using `libbossApple`.

Dependency graph:
- `libboss` is the core package.
- `libboss-apple` depends on `libboss`.
- `bossctl` depends on `libboss-apple`.
- `boss-apple-app` depends on `libboss-apple`.
- `boss-macos` depends on `libboss-apple` and `boss-apple-app`.
- `boss-ios` depends on `libboss-apple` and `boss-apple-app`.

Platform constraints:
- `libboss-apple`: iOS 17+, macOS 14+
- `bossctl`, `boss-macos`: macOS 14+

Working guidance:
- Run SwiftPM commands from the relevant package directory.
- Treat `packages/*/.build/` as generated output, not source.
