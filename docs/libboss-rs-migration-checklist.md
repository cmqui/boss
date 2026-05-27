# libboss Migration Checklist

Last reviewed: 2026-05-23

This checklist tracks the remaining work to finish the migration to Rust `libboss` and remove the deprecated Swift implementation. It replaces the older phase list that was written while `packages/core/libboss` still referred to the Swift package.

## Current Repo Snapshot

- `packages/core/libboss` is now the Rust workspace and the intended source of truth for protocol, codec, and session logic.
  Files:
  [packages/core/libboss/README.md](/Users/ciara/Code/boss/packages/core/libboss/README.md:1)
  [packages/core/libboss/Cargo.toml](/Users/ciara/Code/boss/packages/core/libboss/Cargo.toml:1)

- The old Swift implementation now lives in `packages/old/libboss` and is explicitly deprecated.
  Files:
  [packages/old/libboss/README.md](/Users/ciara/Code/boss/packages/old/libboss/README.md:1)
  [packages/old/libboss/Package.swift](/Users/ciara/Code/boss/packages/old/libboss/Package.swift:1)

- `libboss-apple` no longer has a SwiftPM dependency on the old Swift package. Its only package dependency is the local C target used to talk to the Rust FFI.
  Files:
  [packages/core/libboss-apple/Package.swift](/Users/ciara/Code/boss/packages/core/libboss-apple/Package.swift:1)

- `bossctl`, `boss-macos`, `boss-apple-app`, and `boss-ios` all consume `libbossApple` or `BossAppleApp`; none of the active app or CLI targets import the deprecated Swift `libboss` module directly.
  Files:
  [packages/ui/bossctl/Package.swift](/Users/ciara/Code/boss/packages/ui/bossctl/Package.swift:1)
  [packages/ui/apple/boss-macos/Package.swift](/Users/ciara/Code/boss/packages/ui/apple/boss-macos/Package.swift:1)
  [packages/ui/apple/app-core/Package.swift](/Users/ciara/Code/boss/packages/ui/apple/app-core/Package.swift:1)
  [packages/ui/apple/boss-ios/BossiOS.xcodeproj/project.pbxproj](/Users/ciara/Code/boss/packages/ui/apple/boss-ios/BossiOS.xcodeproj/project.pbxproj:1)

## Exit Criteria

- `libboss-apple`, `bossctl`, `boss-macos`, `boss-apple-app`, and `boss-ios` no longer depend on any source from `packages/old/libboss`.
- Public Swift APIs no longer expose deprecated Swift-core ownership or naming that assumes the old package is still the implementation authority.
- Rust is the only production protocol/session implementation.
- The Rust runtime/linking model is explicit and reproducible in local development, CI, and release builds.
- Swift-side tests cover the public Apple bridge surface well enough to delete `libboss-OLD` with confidence.
- Hardware validation is complete on at least one real supported device path per transport/characteristic mode that the product intends to support.

## Phase 1: Rust Protocol and Session Ownership

- [x] Make Rust `libboss` the active source of truth for protocol/session logic.
  Result:
  The active `packages/core/libboss` directory is the Rust workspace, while the legacy Swift code was moved aside to `packages/old/libboss`.
  Files:
  [packages/core/libboss/README.md](/Users/ciara/Code/boss/packages/core/libboss/README.md:1)
  [packages/old/libboss/README.md](/Users/ciara/Code/boss/packages/old/libboss/README.md:1)

- [x] Remove Swift-session fallback ownership from `libboss-apple`.
  Result:
  `BossAppleSession` now requires the Rust bridge for bootstrap, reads, writes, and stream setup rather than constructing Swift-core sessions as a production fallback.
  Files:
  [packages/core/libboss-apple/Sources/libbossApple/BossAppleSession.swift](/Users/ciara/Code/boss/packages/core/libboss-apple/Sources/libbossApple/BossAppleSession.swift:1)
  [packages/core/libboss-apple/Sources/libbossApple/BossRustSessionBridge.swift](/Users/ciara/Code/boss/packages/core/libboss-apple/Sources/libbossApple/BossRustSessionBridge.swift:1)

- [x] Route packet encode/decode and BLE framing through Rust-owned helpers.
  Result:
  `BossAppleLink` and the Rust transport bridge segment and reassemble via FFI calls instead of using the old Swift codec/framing types.
  Files:
  [packages/core/libboss-apple/Sources/libbossApple/BossAppleLink.swift](/Users/ciara/Code/boss/packages/core/libboss-apple/Sources/libbossApple/BossAppleLink.swift:1)
  [packages/core/libboss-apple/Sources/libbossApple/RustBridge/BossRustSessionBridge+Transport.swift](/Users/ciara/Code/boss/packages/core/libboss-apple/Sources/libbossApple/RustBridge/BossRustSessionBridge+Transport.swift:1)
  [packages/core/libboss-apple/Sources/libbossApple/RustBridge/BossRustCodecBridge.swift](/Users/ciara/Code/boss/packages/core/libboss-apple/Sources/libbossApple/RustBridge/BossRustCodecBridge.swift:1)

- [x] Re-home shared Bose BLE constants into `libboss-apple`.
  Result:
  Active Apple transport/discovery code uses `AppleBoseUUIDs`, not the old Swift-core constant owner.
  Files:
  [packages/core/libboss-apple/Sources/libbossApple/AppleBoseUUIDs.swift](/Users/ciara/Code/boss/packages/core/libboss-apple/Sources/libbossApple/AppleBoseUUIDs.swift:1)
  [packages/core/libboss-apple/Sources/libbossApple/AppleBleBossTransport.swift](/Users/ciara/Code/boss/packages/core/libboss-apple/Sources/libbossApple/AppleBleBossTransport.swift:1)
  [packages/core/libboss-apple/Sources/libbossApple/AppleBossDeviceDiscovery.swift](/Users/ciara/Code/boss/packages/core/libboss-apple/Sources/libbossApple/AppleBossDeviceDiscovery.swift:1)

## Phase 2: Public Swift API Ownership

- [x] Stop exposing old Swift-core transport/session types from the Apple layer.
  Result:
  The raw-link escape hatch is gone from the public API surface, and the consumer-facing types live under Apple-owned `BossApple...` names.
  Files:
  [packages/core/libboss-apple/Sources/libbossApple/BossAppleController.swift](/Users/ciara/Code/boss/packages/core/libboss-apple/Sources/libbossApple/BossAppleController.swift:1)
  [packages/core/libboss-apple/Sources/libbossApple/BossApplePublicTypes.swift](/Users/ciara/Code/boss/packages/core/libboss-apple/Sources/libbossApple/BossApplePublicTypes.swift:1)

- [x] Move app- and CLI-facing type usage onto `libbossApple`.
  Result:
  Active consumers import `libbossApple` or `BossAppleApp`, not the deprecated Swift `libboss` module.
  Files:
  [packages/ui/bossctl/Sources/bossctl/Main.swift](/Users/ciara/Code/boss/packages/ui/bossctl/Sources/bossctl/Main.swift:1)
  [packages/ui/apple/boss-macos/Sources/BossMacOS/ContentView.swift](/Users/ciara/Code/boss/packages/ui/apple/boss-macos/Sources/BossMacOS/ContentView.swift:1)
  [packages/ui/apple/app-core/Sources/BossAppleApp/BossAppViewModel.swift](/Users/ciara/Code/boss/packages/ui/apple/app-core/Sources/BossAppleApp/BossAppViewModel.swift:1)
  [packages/ui/apple/boss-ios/Sources/BossiOS/BossIOSRootView.swift](/Users/ciara/Code/boss/packages/ui/apple/boss-ios/Sources/BossiOS/BossIOSRootView.swift:1)

- [x] Decide whether any public `BossApple...` compatibility shims should be simplified further.
  Result:
  A final pass found one real migration-era survivor: the public `BossAppleSettingsSnapshot` / `settingsSnapshot()` surface, which active app and CLI targets no longer use now that typed Apple APIs cover the supported reads. That snapshot type has been reduced to an internal implementation detail used by the Rust bridge and tests. The remaining public `BossApple...` model surface is intentional consumer API, not legacy `libboss` compatibility scaffolding.
  Files:
  [packages/core/libboss-apple/Sources/libbossApple/BossApplePublicTypes.swift](/Users/ciara/Code/boss/packages/core/libboss-apple/Sources/libbossApple/BossApplePublicTypes.swift:1027)
  [packages/core/libboss-apple/Sources/libbossApple/BossAppleController.swift](/Users/ciara/Code/boss/packages/core/libboss-apple/Sources/libbossApple/BossAppleController.swift:230)
  [packages/core/libboss-apple/Sources/libbossApple/BossAppleSession.swift](/Users/ciara/Code/boss/packages/core/libboss-apple/Sources/libbossApple/BossAppleSession.swift:108)

## Phase 3: Remove Build-Time Dependencies on the Swift Implementation

- [x] Remove direct package dependencies on the old Swift `libboss`.
  Result:
  The active package manifests no longer reference `../libboss`; the old code is isolated under `../libboss-OLD`.
  Files:
  [packages/core/libboss-apple/Package.swift](/Users/ciara/Code/boss/packages/core/libboss-apple/Package.swift:1)
  [packages/ui/bossctl/Package.swift](/Users/ciara/Code/boss/packages/ui/bossctl/Package.swift:1)
  [packages/ui/apple/boss-macos/Package.swift](/Users/ciara/Code/boss/packages/ui/apple/boss-macos/Package.swift:1)
  [packages/ui/apple/app-core/Package.swift](/Users/ciara/Code/boss/packages/ui/apple/app-core/Package.swift:1)

- [x] Remove direct source imports of the deprecated Swift `libboss` module from active products.
  Result:
  The remaining `@testable import libboss` references are confined to `packages/old/libboss/Tests`.
  Files:
  [packages/old/libboss/Tests/libbossTests/libbossTests.swift](/Users/ciara/Code/boss/packages/old/libboss/Tests/libbossTests/libbossTests.swift:1)
  [packages/old/libboss/Tests/libbossTests/BossSettingsSnapshotTests.swift](/Users/ciara/Code/boss/packages/old/libboss/Tests/libbossTests/BossSettingsSnapshotTests.swift:1)

## Phase 4: Remove Remaining Low-Level Swift Protocol Glue

- [x] Remove dependence on the old Swift codec/framing/session implementation.
  Result:
  The active Apple code no longer imports or constructs `BossPacketSession`, `BootstrapSession`, `BleSegmentation`, `BleSegmentReassembler`, or `BmapCodec` from the legacy package.

- [x] Decide whether to keep or collapse the remaining Swift-side FFI adapter layer.
  Result:
  The remaining Swift transport glue should stay on the Swift side, but remain intentionally thin. `CoreBluetooth` integration, task/stream lifecycle management, and host-language adaptation belong in Swift; BMAP semantics, framing rules, parsing, and session behavior belong in Rust. Phase 4 should therefore trim only Swift code that still performs protocol reasoning, not eliminate the Apple-side adapter layer altogether.
  Files:
  [packages/core/libboss-apple/Sources/libbossApple/BossAppleLink.swift](/Users/ciara/Code/boss/packages/core/libboss-apple/Sources/libbossApple/BossAppleLink.swift:1)
  [packages/core/libboss-apple/Sources/libbossApple/RustBridge/BossRustSessionBridge+Transport.swift](/Users/ciara/Code/boss/packages/core/libboss-apple/Sources/libbossApple/RustBridge/BossRustSessionBridge+Transport.swift:1)

## Phase 5: Remove Direct Legacy Usage From Apps and CLI

- [x] Remove direct `libboss` usage from `bossctl`.
  Result:
  `bossctl` imports `libbossApple` only and no longer exposes the old raw BMAP command path.
  Files:
  [packages/ui/bossctl/Sources/bossctl](/Users/ciara/Code/boss/packages/ui/bossctl/Sources/bossctl:1)

- [x] Remove direct `libboss` usage from `boss-macos`.
  Result:
  The macOS app imports `BossAppleApp` and `libbossApple`, not the deprecated Swift core module.
  Files:
  [packages/ui/apple/boss-macos/Sources/BossMacOS](/Users/ciara/Code/boss/packages/ui/apple/boss-macos/Sources/BossMacOS:1)

- [x] Keep shared app logic on top of the Apple layer.
  Result:
  `boss-apple-app` and `boss-ios` sit above `libbossApple` and do not reach into legacy Swift-core code.
  Files:
  [packages/ui/apple/app-core/Sources/BossAppleApp](/Users/ciara/Code/boss/packages/ui/apple/app-core/Sources/BossAppleApp:1)
  [packages/ui/apple/boss-ios/Sources/BossiOS](/Users/ciara/Code/boss/packages/ui/apple/boss-ios/Sources/BossiOS:1)

## Phase 6: Replace Migration-Era Runtime Loading With a Final Integration Model

- [x] Define the supported Rust runtime model for each environment.
  Decision:
  The repo should treat Rust runtime availability as an explicit build/deployment contract, not a best-effort loader detail.
  Support matrix:
  `libboss-apple` SwiftPM local tests:
  debug-only repo-relative probing is allowed as a developer convenience; explicit `LIBBOSS_FFI_DYLIB` remains supported; this is not a release or CI contract.
  `boss-macos` local Xcode builds:
  bundled dylib loading is supported for local development; static linking may remain available as a secondary local scheme while cleanup continues.
  `boss-ios` local Xcode builds:
  static linking is the supported model.
  CI builds:
  Rust artifacts should be built explicitly before Swift/Xcode builds or tests; CI should not rely on ambient repo probing as the primary contract.
  macOS self-contained app releases outside Homebrew:
  static linking is the preferred model.
  macOS Homebrew distribution for `bossctl` and `boss-macos`:
  a packaged shared `libboss_ffi.dylib` is the preferred model, with one shared runtime formula named `libboss`, a CLI formula named `bossctl`, and a macOS app cask named `boss-ui`.
  Homebrew runtime-location contract:
  the Homebrew channel should set `LIBBOSS_FFI_HOMEBREW_PREFIX` for `bossctl` and `boss-ui`, pointing at the stable Homebrew `opt` prefix for the shared runtime formula.
  Expected shared runtime path:
  `$(brew --prefix)/opt/libboss/lib/libboss_ffi.dylib`
  Homebrew compatibility contract:
  `libboss`, `bossctl`, and `boss-ui` should be released in lockstep from the same repo version and validated together as one compatible distribution set, rather than relying on loose runtime version-range negotiation.
  iOS release builds:
  static linking is the supported model.
  Consequence:
  Repo-relative probing is development-only fallback behavior. Future loader cleanup should remove or fence off any paths that do not match this matrix, and macOS distribution work should distinguish clearly between self-contained static app releases and the shared-dylib Homebrew channel.

- [x] Narrow opportunistic `dlopen` probing to an explicit supported search policy.
  Result:
  Dynamic loading is now limited to the named supported channels: `LIBBOSS_FFI_DYLIB`, `LIBBOSS_FFI_HOMEBREW_PREFIX`, and bundled framework dylibs, while compile-time static linking remains separate via `LIBBOSS_STATIC_LINKED`. Generic process-symbol probing has been removed, repo-relative lookup is now explicitly a dev-only fallback, and the loader logs which runtime channel won.
  Files:
  [packages/core/libboss-apple/Sources/libbossApple/RustBridge/BossRustSessionBridge+Runtime.swift](/Users/ciara/Code/boss/packages/core/libboss-apple/Sources/libbossApple/RustBridge/BossRustSessionBridge+Runtime.swift:1)
  [packages/core/libboss-apple/README.md](/Users/ciara/Code/boss/packages/core/libboss-apple/README.md:1)

- [x] Unify or intentionally document the current macOS and iOS linkage split.
  Result:
  The split is now intentional and documented. `boss-ios` remains static-link only, `boss-macos` keeps a local dynamic channel for development plus a static option, self-contained macOS app releases prefer static linking, and the Homebrew channel prefers one shared packaged `libboss_ffi.dylib` for `bossctl` and `boss-macos`.
  Files:
  [packages/ui/apple/boss-macos/project.yml](/Users/ciara/Code/boss/packages/ui/apple/boss-macos/project.yml:1)
  [packages/ui/apple/boss-macos/scripts/build-libboss-ffi.sh](/Users/ciara/Code/boss/packages/ui/apple/boss-macos/scripts/build-libboss-ffi.sh:1)
  [packages/ui/apple/boss-ios/project.yml](/Users/ciara/Code/boss/packages/ui/apple/boss-ios/project.yml:1)
  [packages/ui/apple/boss-ios/scripts/build-libboss-ffi.sh](/Users/ciara/Code/boss/packages/ui/apple/boss-ios/scripts/build-libboss-ffi.sh:1)
  [packages/core/libboss-apple/README.md](/Users/ciara/Code/boss/packages/core/libboss-apple/README.md:1)

- [ ] Remove the remaining migration-era runtime ambiguity once the supported build model is settled.
  Note:
  The product path is already Rust-only for real functionality, and repo-relative fallback is now explicitly dev-only. The repo now has concrete packaging entrypoints and staged Homebrew outputs for `libboss`, `bossctl`, and `boss-ui`; the runtime also recognizes the standard Homebrew `opt/libboss` locations directly, so the cask app no longer depends on a launcher wrapper to find the shared dylib. The release artifact policy is now: split per-architecture macOS archives for `libboss` and `bossctl`, one universal macOS app archive for `boss-ui`, and an explicit notarized release path for the cask archive when `BOSS_MACOS_DEVELOPER_IDENTITY` and `BOSS_MACOS_NOTARY_KEYCHAIN_PROFILE` are provided. The remaining work is tightening this into automated CI/release jobs and validating the notarized path on a machine with a real Developer ID Application identity available.
  Files:
  [Makefile](/Users/ciara/Code/boss/Makefile:1)
  [packaging/homebrew/README.md](/Users/ciara/Code/boss/packaging/homebrew/README.md:1)
  [packaging/shared/README.md](/Users/ciara/Code/boss/packaging/shared/README.md:1)
  [packaging/homebrew/Formula/libboss.rb](/Users/ciara/Code/boss/packaging/homebrew/Formula/libboss.rb:1)
  [packaging/homebrew/Formula/bossctl.rb](/Users/ciara/Code/boss/packaging/homebrew/Formula/bossctl.rb:1)
  [packaging/homebrew/Casks/boss-ui.rb](/Users/ciara/Code/boss/packaging/homebrew/Casks/boss-ui.rb:1)

## Phase 7: Test Coverage Before Deletion

- [x] Keep Rust crate tests in place for the Rust source of truth.
  Current coverage:
  `libboss-core/tests/core_parity.rs`
  `libboss-session/src/tests.rs`
  `libboss-ffi/src/tests.rs`
  Files:
  [packages/core/libboss/libboss-core/tests/core_parity.rs](/Users/ciara/Code/boss/packages/core/libboss/libboss-core/tests/core_parity.rs:1)
  [packages/core/libboss/libboss-session/src/tests.rs](/Users/ciara/Code/boss/packages/core/libboss/libboss-session/src/tests.rs:1)
  [packages/core/libboss/libboss-ffi/src/tests.rs](/Users/ciara/Code/boss/packages/core/libboss/libboss-ffi/src/tests.rs:1)

- [x] Swift-side bridge and public-API coverage now make the Rust-first cutover deletion-safe.
  Current coverage:
  `AppleBleBossTransportTests.swift`
  `BossAppleControllerErrorTests.swift`
  `BossAppleSessionPublicApiTests.swift`
  `BossAppleSettingsSnapshotTests.swift`
  `BossRustSessionBridgeConversionTests.swift`
  `BossRustFfiRuntimeSearchPolicyTests.swift`
  Files:
  [packages/core/libboss-apple/Tests/libbossAppleTests](/Users/ciara/Code/boss/packages/core/libboss-apple/Tests/libbossAppleTests:1)

- [x] Higher-confidence Swift tests exercise public Apple APIs through the Rust bridge seam.
  Covered paths:
  bootstrap
  current audio mode read/write
  audio mode settings read/write
  equalizer read/write
  favorites
  custom mode save/delete/update paths
  update streams
  runtime loading failure modes

- [x] Downstream Apple-layer consumers already have basic unit coverage.
  Files:
  [packages/ui/bossctl/Tests/bossctlTests](/Users/ciara/Code/boss/packages/ui/bossctl/Tests/bossctlTests:1)
  [packages/ui/apple/app-core/Tests/BossAppleAppTests](/Users/ciara/Code/boss/packages/ui/apple/app-core/Tests/BossAppleAppTests:1)

## Phase 8: Hardware Validation

- [ ] Run a fresh real-device parity pass now that the repo structure has stabilized around Rust-first ownership.

- [ ] Validate live reads and writes for:
  - [x] current mode
  - [x] mode settings
  - [x] equalizer
  - [ ] standby timer
  - [ ] wear detection
  - [ ] auto-aware
  - [x] auto-play-pause
  - [ ] auto-answer
  - [ ] volume control
  - [x] favorites
  - [x] custom modes

- [x] Validate stream behavior for:
  - [x] current audio mode updates
  - [x] audio mode settings updates
  - [x] equalizer updates
  - [x] device settings updates
  - [x] audio mode catalog updates

- [ ] Confirm behavior on the characteristic preference paths the apps still retry across.
  Files:
  [packages/core/libboss-apple/Sources/libbossApple/BossAppleSession.swift](/Users/ciara/Code/boss/packages/core/libboss-apple/Sources/libbossApple/BossAppleSession.swift:1)

## Phase 9: Final Archival State

- [ ] Freeze `packages/old/libboss` as archival-only code until the remaining runtime/test/hardware items are done.

- [ ] Keep `packages/old/libboss` archived in place with no active product dependencies, no new feature work, and clear documentation that it is retained for reference only.

- [ ] Clean up any docs, scripts, or comments that still speak about migrating from Swift `libboss` as if the active package had not already moved to Rust.
  Files:
  [packages/core/libboss-apple/README.md](/Users/ciara/Code/boss/packages/core/libboss-apple/README.md:1)
  [packages/ui/apple/boss-macos/README.md](/Users/ciara/Code/boss/packages/ui/apple/boss-macos/README.md:1)
  [docs/testing-roadmap.md](/Users/ciara/Code/boss/docs/testing-roadmap.md:1)

## Recommended Execution Order

- [ ] 1. Decide the final Rust linkage/loading model for SwiftPM, Xcode, CI, macOS, and iOS.
- [x] 2. Add Swift-side bridge and public-API tests that make the Rust cutover deletion-safe.
- [ ] 3. Run real hardware validation on the Rust-only path.
- [ ] 4. Trim any leftover compatibility surface that is no longer buying anything.
- [ ] 5. Lock `packages/old/libboss` into archival-only status and clean up migration-era documentation.
