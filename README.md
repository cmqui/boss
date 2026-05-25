# Boss

Tools and UI experiments for controlling Bose devices over BMAP.

## Packages

- `packages/libboss`: Rust source of truth for portable BMAP protocol/session logic
- `packages/libboss-OLD`: deprecated Swift reference implementation retained temporarily
- `packages/libboss-apple`: Apple/CoreBluetooth transport and controller APIs
- `packages/bossctl`: CLI for inspecting and changing device settings
- `packages/boss-apple-app`: apple-specific shared app logic
- `packages/boss-macos`: macOS app UI
- `packages/boss-ios`: iOS app UI

## Quick Start

Build the Rust FFI once:

```sh
cd packages/libboss
cargo build -p libboss-ffi
```

CLI:

```sh
cd packages/bossctl
swift run bossctl --help
```

macOS app:

```sh
cd packages/boss-macos
swift run Boss
```
