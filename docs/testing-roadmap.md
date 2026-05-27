# Testing Roadmap

## Goals

- keep protocol, FFI, app-state, and CLI behavior stable as the repo grows
- catch regressions close to the package boundary where they are introduced
- make hardware-dependent code testable without requiring real Bose devices
- turn every production bug into a pinned regression test

## Current State

The repo already has meaningful Rust coverage in `packages/core/libboss`:

- `packages/core/libboss/libboss-core/tests/core_parity.rs`
- `packages/core/libboss/libboss-session/src/tests.rs`
- `packages/core/libboss/libboss-ffi/src/tests.rs`

The thinner areas are the higher-level Swift packages:

- `packages/core/libboss-apple` has a small XCTest surface in `Tests/libbossAppleTests/AppleBleBossTransportTests.swift`
- `packages/ui/apple/app-core` has one smoke test in `Tests/BossAppleAppTests/BossAppleAppTests.swift`
- `packages/ui/bossctl` currently has no test target
- `packages/ui/apple/boss-macos` and `packages/ui/apple/boss-ios` do not appear to have meaningful automated tests yet

That means the core protocol layer is in better shape than the Apple bridge, app state, and CLI surfaces that users interact with directly.

## Test Pyramid For This Repo

The repo should evolve toward this split:

- `libboss`: dense unit and integration coverage in Rust
- `libboss-apple`: contract tests around FFI, runtime loading, data conversion, and retry/fallback behavior
- `boss-apple-app`: state-machine tests for `BossAppViewModel`
- `bossctl`: parser, dispatch, and output tests
- `boss-macos` and `boss-ios`: a small number of app smoke tests and launch/navigation checks

The main principle is to keep most logic tests below the UI layer and above raw hardware access.

## Package Plan

### `packages/core/libboss`

This is already the strongest test area. Keep expanding it, but optimize for contract coverage rather than raw line count.

Add next:

- fixture-driven tests for real packet captures from supported devices
- regression tests for every parsing or session bug fixed in the future
- more negative tests for malformed packets, truncated payloads, invalid frame sizes, and unsupported operators
- property-style tests for packet encode/decode roundtrips and BLE segmentation/reassembly invariants

Good homes:

- `packages/core/libboss/libboss-core/tests/codec_regressions.rs`
- `packages/core/libboss/libboss-core/tests/transport_properties.rs`
- `packages/core/libboss/libboss-session/tests/session_regressions.rs`
- `packages/core/libboss/libboss-ffi/tests/ffi_contract.rs`

### `packages/core/libboss-apple`

This package is the main gap between well-tested Rust logic and user-facing Swift code. It should get contract-style tests around:

- `BossRustSessionBridge`
- `BossRustCodecBridge`
- `BossAppleSession`
- `BossAppleController`
- snapshot decoding and conversion logic in `BossApplePublicTypes.swift`

High-value test areas:

- runtime loading behavior in `RustBridge/BossRustSessionBridge+Runtime.swift`
- conversion behavior in `RustBridge/BossRustSessionBridge+Conversions.swift`
- transport fallback and retry behavior in `BossAppleSession.swift` and `Controller/BossAppleController+Transport.swift`
- unsupported vs unavailable vs timed-out distinctions in `BossAppleController+Errors.swift`
- snapshot decoding and projection behavior in `BossApplePublicTypes.swift`

Recommended new test files:

- `packages/core/libboss-apple/Tests/libbossAppleTests/BossRustSessionBridgeRuntimeTests.swift`
- `packages/core/libboss-apple/Tests/libbossAppleTests/BossRustSessionBridgeConversionTests.swift`
- `packages/core/libboss-apple/Tests/libbossAppleTests/BossAppleSessionRetryTests.swift`
- `packages/core/libboss-apple/Tests/libbossAppleTests/BossAppleControllerErrorTests.swift`
- `packages/core/libboss-apple/Tests/libbossAppleTests/BossAppleSettingsSnapshotTests.swift`

Structural prerequisite:

- introduce small protocols for runtime loading, BLE transport/discovery, and session/controller construction so hardware-facing code can be replaced with fakes in tests

### `packages/ui/apple/app-core`

This package should be treated as a state-management layer, not just a SwiftUI shell. The main test target should be `BossAppViewModel`.

Files to target:

- `BossAppViewModel.swift`
- `BossAppViewModel+Discovery.swift`
- `BossAppViewModel+Lifecycle.swift`
- `BossAppViewModel+ModeActions.swift`
- `BossAppViewModel+Profiles.swift`

High-value scenarios:

- startup transitions from waiting to connected state
- refresh and reconnect flows
- busy-state handling during writes
- error surfacing and recovery
- update stream application to current mode, equalizer, and device settings
- optimistic state updates versus server-confirmed state

Recommended new test files:

- `packages/ui/apple/app-core/Tests/BossAppleAppTests/BossAppViewModelLifecycleTests.swift`
- `packages/ui/apple/app-core/Tests/BossAppleAppTests/BossAppViewModelDiscoveryTests.swift`
- `packages/ui/apple/app-core/Tests/BossAppleAppTests/BossAppViewModelModeActionTests.swift`
- `packages/ui/apple/app-core/Tests/BossAppleAppTests/BossAppViewModelProfilesTests.swift`

Structural prerequisite:

- inject a fake `BossAppleSession` / `BossAppleController` layer instead of constructing concrete production objects directly inside the view model

### `packages/ui/bossctl`

`bossctl` is currently unprotected and should be the first Swift package expanded. It has a lot of pure logic that is easy to test:

- `ArgumentParser.swift`
- `Command.swift`
- `ConnectionOptions.swift`
- `SettingsCommand.swift`
- `AudioModeCommand.swift`
- `Formatting.swift`
- `Output.swift`

Add a test target in `packages/ui/bossctl/Package.swift`, then create:

- `packages/ui/bossctl/Tests/bossctlTests/ArgumentParserTests.swift`
- `packages/ui/bossctl/Tests/bossctlTests/CommandParsingTests.swift`
- `packages/ui/bossctl/Tests/bossctlTests/ConnectionOptionsTests.swift`
- `packages/ui/bossctl/Tests/bossctlTests/SettingsCommandTests.swift`
- `packages/ui/bossctl/Tests/bossctlTests/AudioModeCommandTests.swift`
- `packages/ui/bossctl/Tests/bossctlTests/FormattingTests.swift`

After parser coverage, add dispatch/output tests that assert:

- expected stdout for successful bootstrap/settings/audio-mode flows
- expected stderr and exit behavior for usage errors
- graceful handling of unsupported settings and runtime failures

Structural prerequisite:

- move command execution behind a small protocol or runner type so `Main.swift` is not the only place that can drive a command

### `packages/ui/apple/boss-macos` and `packages/ui/apple/boss-ios`

These should stay thin. Do not duplicate business logic tests that belong in `boss-apple-app`.

Add only a small set of app-level checks:

- app launch smoke test
- one navigation test for the primary workflow
- one error presentation test

If UI testing becomes expensive, keep coverage shallow here and push logic tests down into `boss-apple-app`.

## First 10 Tests To Add

Add these in order.

1. `bossctl` command parsing for `bootstrap`, `settings`, and `audio-mode` happy paths.
2. `bossctl` invalid argument coverage for missing values, bad UUIDs, invalid timeouts, and unsupported enum values.
3. `bossctl` formatting/output tests for bootstrap and key settings commands.
4. `libboss-apple` tests for `BossAppleController.isUnavailableSettingReadError` across all expected error variants.
5. `libboss-apple` snapshot decoding tests for truncated length prefixes, invalid packet lengths, and composite fallback behavior.
6. `libboss-apple` conversion tests for FFI structs into Swift public types, especially observed settings and audio mode config values.
7. `libboss-apple` session retry tests covering automatic secure/unsecure fallback and timeout handling.
8. `boss-apple-app` lifecycle tests for waiting, connecting, connected, and error transitions.
9. `boss-apple-app` mode action tests for set-current-mode, favorite/unfavorite, and equalizer updates.
10. `libboss` fixture regression tests from real packet captures covering one full bootstrap and one settings snapshot.

## Injection Seams To Add

The Swift packages need a few narrow seams before test coverage scales cleanly.

Add protocols or lightweight adapters for:

- BLE discovery and transport creation
- Rust FFI runtime lookup/loading
- session/controller factories
- clock/sleep behavior for retry logic and timeout-driven flows
- output writing in `bossctl`

Without these seams, tests will stay brittle and too dependent on concrete runtime behavior.

## Fixture Strategy

Create a shared fixture set for representative device interactions.

Suggested layout:

- `packages/core/libboss/testdata/bootstrap/`
- `packages/core/libboss/testdata/settings/`
- `packages/core/libboss-apple/Tests/Fixtures/`

Each fixture should contain:

- raw request/response packet bytes
- expected decoded values
- notes about device model / firmware version when known

Use these fixtures in both Rust and Swift contract tests where practical. That gives cross-layer confidence that the FFI boundary has not drifted semantically.

## CI Plan

Minimum CI test matrix:

- `cd packages/core/libboss && cargo test`
- `cd packages/core/libboss-apple && swift test`
- `cd packages/ui/bossctl && swift test`
- `cd packages/ui/apple/app-core && swift test`

Later, add:

- app-target smoke tests for `boss-macos`
- simulator-based smoke tests for `boss-ios`

CI policy:

- every bug fix should include at least one regression test
- no new package-level command or state transition should ship without tests
- failures in parser, FFI contract, and snapshot decoding tests should block merges

## Milestones

### Milestone 1: Close the obvious holes

- add a `bossctl` test target
- expand `libboss-apple` beyond the current small transport test file
- expand `boss-apple-app` beyond the current smoke test
- wire package test commands into CI

### Milestone 2: Make Swift logic injectable

- add protocols for runtime loading, transport creation, and session/controller factories
- refactor `BossAppViewModel` and `bossctl` command execution to use those seams
- add fakes for test-only execution paths

### Milestone 3: Add contract fixtures

- capture representative bootstrap/settings data
- create shared decode expectations
- test those fixtures in Rust and Swift

### Milestone 4: Regression discipline

- require bug-fix tests
- keep a running regression suite for protocol quirks and device-specific behavior

## Suggested Execution Order

If this is implemented incrementally, do it in this order:

1. add `bossctl` tests
2. add `libboss-apple` snapshot/error/conversion tests
3. make `boss-apple-app` injectable and add lifecycle/action tests
4. add fixture-based cross-layer tests
5. add thin app smoke tests

This order gives the fastest quality gain for the least implementation cost.
