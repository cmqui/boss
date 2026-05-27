# Boss

Tools and UI experiments for controlling Bose devices over BMAP.

## Packages

- `packages/core/libboss`: Rust source of truth for portable BMAP protocol/session logic
- `packages/old/libboss`: deprecated Swift reference implementation retained temporarily
- `packages/core/libboss-apple`: Apple/CoreBluetooth transport and controller APIs
- `packages/ui/bossctl`: CLI for inspecting and changing device settings
- `packages/ui/apple/app-core`: apple-specific shared app logic
- `packages/ui/apple/boss-macos`: macOS app UI
- `packages/ui/apple/boss-ios`: iOS app UI

## Quick Start

Build the Rust FFI once:

```sh
cd packages/core/libboss
cargo build -p libboss-ffi
```

CLI:

```sh
cd packages/ui/bossctl
swift run bossctl --help
```

macOS app:

```sh
cd packages/ui/apple/boss-macos
swift run Boss
```

## Docs

- [docs/README.md](docs/README.md) for protocol notes and planning documents
