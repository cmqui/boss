# libboss-apple

`libboss-apple` provides the Apple/CoreBluetooth transport layer and typed async APIs on top of Rust `libboss`.

Current scope:

- `CoreBluetooth` discovery and connection flow for Bose BLE peripherals
- Bose BMAP service and characteristic handling
- ATT-MTU-aware BLE writes and notification ingestion
- typed controller/session APIs for macOS and iOS apps
- `boss-bootstrap` for live hardware validation

## Rust FFI Runtime

Session APIs such as `bootstrap()` require Rust `libboss-ffi`, either via:

- a runtime-loaded `liblibboss_ffi.dylib`
- symbols already linked into the current process
- direct static linking with `LIBBOSS_STATIC_LINKED`

Build the dylib:

```sh
cd packages/libboss
cargo build -p libboss-ffi
```

At runtime, `BossRustSessionBridge` looks for the dylib in the app bundle `Frameworks/`, repo-relative build paths, or `LIBBOSS_FFI_DYLIB`.

The `boss-macos` Xcode project supports both runtime dylib loading and a static-link scheme. It runs `scripts/build-libboss-ffi.sh` before each build to compile Rust, and dynamic builds also copy the dylib into `Boss.app/Contents/Frameworks`.

## Running

```sh
cd packages/libboss && cargo build -p libboss-ffi
cd ../libboss-apple
swift run boss-bootstrap --name Bose --timeout 20
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

## Debug Logging

- `LIBBOSS_DEBUG=1` enables protocol/session tracing from Rust `libboss`
- `LIBBOSS_FFI_LOG=1` enables Rust FFI loader/runtime logs
- `LIBBOSS_APPLE_DEBUG=1` enables lifecycle and discovery logs
- `LIBBOSS_APPLE_DEBUG_PACKETS=1` additionally logs raw BLE write/notification frames
