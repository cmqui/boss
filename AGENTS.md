This repository is a multi-package SwiftPM repo, not a root-level JS workspace.

Packages:
- `packages/libboss`: platform-agnostic BMAP protocol/core logic. Product: `libboss`. Has tests in `Tests/libbossTests`.
- `packages/libboss-apple`: Apple/CoreBluetooth integration and async APIs over `libboss`. Product: `libbossApple`. Also contains the `boss-bootstrap` executable. Has tests in `Tests/libbossAppleTests`.
- `packages/bossctl`: macOS CLI for controlling devices through `libbossApple`.
- `packages/boss-macos`: macOS SwiftUI app using `libboss` and `libbossApple`.

Dependency graph:
- `libboss` is the core package.
- `libboss-apple` depends on `libboss`.
- `bossctl` depends on `libboss` and `libboss-apple`.
- `boss-macos` depends on `libboss` and `libboss-apple`.

Platform constraints:
- `libboss`, `libboss-apple`: iOS 17+, macOS 14+
- `bossctl`, `boss-macos`: macOS 14+

Working guidance:
- Run SwiftPM commands from the relevant package directory.
- Treat `packages/*/.build/` as generated output, not source.
