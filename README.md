# Boss

Tools and UI experiments for controlling Bose devices over BMAP.

## Packages

- `packages/libboss`: core Swift protocol and parsing layer
- `packages/libboss-apple`: Apple/CoreBluetooth transport and controller APIs
- `packages/bossctl`: CLI for inspecting and changing device settings
- `packages/boss-macos`: macOS app UI

## Quick Start

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

Release app bundle:

```sh
cd packages/boss-macos
./scripts/build-release-app.sh
```
