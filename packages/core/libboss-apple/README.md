# libboss-apple

`libboss-apple` provides the Apple/CoreBluetooth transport layer and typed async APIs on top of Rust `libboss`.

Current scope:

- `CoreBluetooth` discovery and connection flow for Bose BLE peripherals
- Bose BMAP service and characteristic handling
- ATT-MTU-aware BLE writes and notification ingestion
- typed controller/session APIs for macOS and iOS apps
- bootstrap support consumed by tools such as `bossctl`

## Rust FFI Runtime

Session APIs such as `bootstrap()` require Rust `libboss-ffi`, either via:

- a runtime-loaded `libboss_ffi.dylib`
- direct static linking with `LIBBOSS_STATIC_LINKED`

Build the dylib:

```sh
cd packages/core/libboss
cargo build -p libboss-ffi
```

At runtime, `BossRustSessionBridge` resolves the Rust FFI in this order:

1. explicitly provided dylib path via `LIBBOSS_FFI_DYLIB`
2. explicitly provided shared Homebrew runtime prefix via `LIBBOSS_FFI_HOMEBREW_PREFIX`
3. standard shared Homebrew paths under `/opt/homebrew/opt/libboss` and `/usr/local/opt/libboss`
4. bundled `Frameworks/libboss_ffi.dylib`
5. repo-relative debug artifact search only for local development and tests

Repo-relative probing is intentionally a development fallback, not the supported release story. You can disable it with `LIBBOSS_FFI_ALLOW_REPOSITORY_SEARCH=0` or re-enable it explicitly with `LIBBOSS_FFI_ALLOW_REPOSITORY_SEARCH=1`.
When `LIBBOSS_FFI_LOG=1` is enabled, the loader reports which runtime channel won and labels repo-relative probing as a dev-only fallback.

Supported runtime channels:

- SwiftPM local development and tests: explicit dylib path or debug-only repo probing
- macOS local Xcode development: bundled dylib or static-link scheme
- macOS Homebrew distribution: shared dylib resolved from one explicit Homebrew runtime prefix
- iOS: static linking

For the shared Homebrew channel, point both `bossctl` and `boss-macos` at the same installed runtime prefix, for example:

```sh
export LIBBOSS_FFI_HOMEBREW_PREFIX="/opt/homebrew/opt/libboss"
```

That resolves `libboss_ffi.dylib` at `"$LIBBOSS_FFI_HOMEBREW_PREFIX/lib/libboss_ffi.dylib"`.

The packaged `boss-ui` cask does not need a launcher wrapper to set that variable because the runtime also checks the standard `opt/libboss` locations directly.

The `boss-macos` Xcode project supports both runtime dylib loading and a static-link scheme. It runs `scripts/build-libboss-ffi.sh` before each build to compile Rust, and dynamic builds also copy the dylib into `Boss.app/Contents/Frameworks`.

## CLI Validation

```sh
cd packages/core/libboss && cargo build -p libboss-ffi
cd ../../ui/bossctl
swift run bossctl bootstrap --name Bose --timeout 20
```

Useful options:

- `--identifier <uuid>` targets a specific peripheral
- `--characteristic automatic|unsecure|secure` overrides the write-characteristic preference
- `--timeout <seconds>` adjusts scan timeout

## Programmatic API

Use `BossAppleController` for one-shot operations:

```swift
import libbossApple

let controller = BossAppleController(
    connection: BossAppleConnectionOptions(nameContains: "Bose")
)

let device = try await controller.bootstrap()
let modes = try await controller.displayableAudioModes()
let currentMode = try await controller.currentAudioMode()
let settings = try await controller.audioModeSettings()
let deviceSettings = try await controller.deviceSettings()

let result = try await controller.setAudioModeSettings(
    BossAppleAudioModeSettingsConfigPatch(cncLevel: 5, spatialAudioMode: .off)
)

let updatedWearDetection = try await controller.setWearDetection(
    BossAppleOnHeadDetectionPatch(
        isEnabled: true,
        isAutoPlayEnabled: true
    )
)
```

Use `BossAppleSession` for a longer-lived connection and repeated refreshes:

```swift
let session = BossAppleSession(
    connection: BossAppleConnectionOptions(nameContains: "Bose")
)

let workspace = try await session.loadWorkspaceSnapshot()

for try await update in session.modeWorkspaceUpdates(interval: .seconds(5)) {
    print(update.currentAudioModeIndex)
}
```

## Further Reading

- [../../docs/bmap-protocol-notes.md](../../docs/bmap-protocol-notes.md) for protocol and BLE transport notes
- [../../docs/current-audio-mode-streaming.md](../../docs/current-audio-mode-streaming.md) for streaming behavior and polling guidance

## Debug Logging

- `LIBBOSS_DEBUG=1` enables protocol/session tracing from Rust `libboss`
- `LIBBOSS_FFI_LOG=1` enables Rust FFI loader/runtime logs
- `LIBBOSS_APPLE_DEBUG=1` enables lifecycle and discovery logs
- `LIBBOSS_APPLE_DEBUG_PACKETS=1` additionally logs raw BLE write/notification frames
