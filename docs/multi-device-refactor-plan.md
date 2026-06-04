# Multi-Device Refactor Plan

Last reviewed: 2026-06-04

## Goal

Refactor Boss so adding support for another Bose product, starting with QC45, is primarily:

- a catalog entry
- a capability profile
- fixture and contract tests
- optional UI assets

instead of a cross-cutting patch through Rust session logic, the Swift bridge, and app state assumptions.

The immediate target is not to implement QC45 yet. The target is to make the codebase structurally ready for:

- full settings control where the device supports it
- graceful fallback where the device or transport does not support a feature
- future support for additional Bose products without repeating the same architectural work

## Current Status

As of 2026-06-04, the architectural refactor is partially complete.

Completed:

- Rust and Swift product catalog types now expose product family and category.
- Rust `libboss-core` has explicit protocol support and Boss capability models.
- Rust bootstrap returns raw protocol support and derived capabilities through `BootstrappedDevice`.
- FFI and `libboss-apple` expose capabilities to Swift.
- `BossAppleSession.loadWorkspaceSnapshot()` returns independent settings, optional audio-mode, and optional equalizer sections.
- App lifecycle loading can open a settings-only workspace without audio modes.
- macOS presentation resolves device artwork by product family/variant and falls back to generic headphones art.

Still open:

- QC45 is not yet a known catalog product. `QC45` exists as a family enum case, but no QC45 product ID, variants, implied protocol support, or capability defaults are registered.
- Capability-aware app and CLI behavior is incomplete outside the main workspace loading path.
- There are no QC45 fixture-backed contract tests yet.

## Remaining Problems

### 1. Product identity and product behavior are mixed together

Current product recognition is a small catalog lookup:

- [packages/core/libboss/libboss-core/src/product.rs](/Users/ciara/Code/boss/packages/core/libboss/libboss-core/src/product.rs:1)
- [packages/core/libboss-apple/Sources/libbossApple/BossApplePublicTypes.swift](/Users/ciara/Code/boss/packages/core/libboss-apple/Sources/libbossApple/BossApplePublicTypes.swift:1)

The catalog now includes family/category fields, but only the QC Ultra 2 HP product is registered. Product support is still not fully data-driven because QC45-specific catalog and capability entries do not exist yet.

### 2. Capability inference is too implicit

`BootstrappedDevice` now exposes raw protocol support and derived capabilities, including which Boss features are:

- supported
- writable
- observable
- transport-limited
- unavailable on this session

Remaining work is to make all session, CLI, and app operations consistently consult this model before attempting unsupported feature paths.

### 3. `BossSession` is organized around one “fully featured” device model

The Rust session surface in [boss_session.rs](/Users/ciara/Code/boss/packages/core/libboss/libboss-session/src/boss_session.rs:1) treats audio modes, custom profiles, favorites, equalizer, and device settings as one canonical feature set. That works for Ultra-style devices, but it is the wrong default for a multi-device library.

### 4. The Apple bridge and app layer assume audio modes are central

The current workspace load path:

- [packages/core/libboss-apple/Sources/libbossApple/BossAppleSession.swift](/Users/ciara/Code/boss/packages/core/libboss-apple/Sources/libbossApple/BossAppleSession.swift:130)
- [packages/ui/apple/app-core/Sources/BossAppleApp/BossAppViewModel+Lifecycle.swift](/Users/ciara/Code/boss/packages/ui/apple/app-core/Sources/BossAppleApp/BossAppViewModel+Lifecycle.swift:81)

now supports:

- a settings workspace
- optional audio mode workspace
- optional equalizer snapshot

Remaining work is to make every action and background stream path behave as cleanly as the initial workspace load for devices with partial support.

### 5. Product-specific presentation is hardcoded

The macOS asset resolver now keys on product family and variant, with generic fallback artwork:

- [packages/ui/apple/boss-macos/Sources/BossMacOS/BossResources.swift](/Users/ciara/Code/boss/packages/ui/apple/boss-macos/Sources/BossMacOS/BossResources.swift:28)

QC45 still needs catalog identity and, optionally, family-specific assets.

## Refactor Objectives

The refactor should satisfy these objectives:

1. Separate device identity from device capabilities.
2. Make capabilities explicit in Rust and visible through the Apple bridge.
3. Ensure unsupported features degrade to structured “unavailable” or “unsupported” states instead of late generic failures.
4. Allow app and CLI surfaces to render and act based on capability presence rather than product-specific assumptions.
5. Keep product-specific protocol quirks localized to capability resolution and feature modules.
6. Make the architecture testable without hardware by driving behavior from fixtures and synthetic capability profiles.

## Target Architecture

### Layer 1: Device Catalog

The catalog is the authoritative source of product identity:

- product id
- code name
- display name
- variant mapping
- product family
- category

This layer should not decide whether a device supports equalizer, custom profiles, or any other Boss feature. It only describes identity.

Suggested Rust types:

```rust
pub enum BossProductFamily {
    QCUltra2,
    QC45,
    Unknown,
}

pub enum BossProductCategory {
    Headphones,
    Earbuds,
    Speaker,
}

pub struct ProductDefinition {
    pub id: u16,
    pub code_name: &'static str,
    pub display_name: &'static str,
    pub family: BossProductFamily,
    pub category: BossProductCategory,
    pub variants: &'static [(u8, &'static str)],
}
```

Swift should mirror the same concepts in `BossApplePublicTypes.swift`.

### Layer 2: Raw Protocol Support

Bootstrap and probing should expose the raw protocol signals the runtime observed, without immediately collapsing them into app semantics.

Suggested Rust shape:

```rust
pub struct BossProtocolSupport {
    pub function_blocks: FunctionBlockSet,
    pub transport_kind: BossTransportKind,
    pub default_device_id: i32,
    pub default_port: i32,
}
```

This keeps raw BMAP support visible and testable.

### Layer 3: Derived Boss Capabilities

Boss has a first-class capability model for its own feature set. Remaining work is to apply it consistently across sessions, app actions, streams, and CLI commands.

Suggested Rust shape:

```rust
pub enum BossFeatureSupport {
    Supported,
    Unsupported,
    Unknown,
}

pub enum BossFeatureAccess {
    ReadOnly,
    ReadWrite,
    Unsupported,
    Unknown,
}

pub struct BossSettingsCapabilities {
    pub standby_timer: BossFeatureAccess,
    pub wear_detection: BossFeatureAccess,
    pub auto_aware: BossFeatureAccess,
    pub auto_play_pause: BossFeatureAccess,
    pub auto_answer: BossFeatureAccess,
    pub volume_control: BossFeatureAccess,
}

pub struct BossAudioModeCapabilities {
    pub modes: BossFeatureSupport,
    pub current_mode: BossFeatureAccess,
    pub settings_config: BossFeatureAccess,
    pub favorites: BossFeatureAccess,
    pub custom_profiles: BossFeatureAccess,
    pub supported_prompts: BossFeatureSupport,
}

pub struct BossSoundCapabilities {
    pub equalizer: BossFeatureAccess,
}

pub struct BossDeviceCapabilities {
    pub settings: BossSettingsCapabilities,
    pub audio_modes: BossAudioModeCapabilities,
    pub sound: BossSoundCapabilities,
}
```

The precise enum names can change, but the structure matters:

- Boss capabilities are distinct from product identity.
- Boss capabilities are distinct from raw function blocks.
- The app should depend on this layer, not on product IDs.

### Layer 4: Feature Workspaces

The previous workspace model was too mode-centric. Swift-facing workspace loading now uses composable feature snapshots, and Rust session internals are split into feature-area modules.

Suggested Rust-side conceptual split:

- device identity snapshot
- settings snapshot
- audio mode snapshot optional
- equalizer snapshot optional

Suggested Swift-facing types:

```swift
public struct BossAppleSettingsWorkspace: Sendable, Equatable {
    public let deviceSettings: BossAppleDeviceSettingsReport
    public let standbyTimer: BossAppleStandbyTimerValue?
}

public struct BossAppleAudioModeWorkspace: Sendable, Equatable {
    public let currentAudioModeIndex: Int
    public let settings: BossAppleAudioModeSettingsConfig
    public let audioModes: [BossAppleAudioModeConfig]
    public let supportedPrompts: [BossAppleAudioModePrompt]
}

public struct BossAppleWorkspaceSnapshot: Sendable, Equatable {
    public let bootstrappedDevice: BossAppleBootstrappedDevice
    public let capabilities: BossAppleDeviceCapabilities
    public let settingsWorkspace: BossAppleSettingsWorkspace
    public let audioModeWorkspace: BossAppleAudioModeWorkspace?
    public let equalizer: BossAppleEqualizerSettings?
}
```

This keeps the app surface explicit:

- audio mode UI exists when `audioModeWorkspace != nil`
- equalizer UI exists when `equalizer != nil`
- device settings UI exists independently

## Module Boundaries

### Rust: `libboss-core`

Responsibilities:

- product catalog
- protocol enums and codecs
- shared capability types
- capability resolver logic inputs and outputs

Current implementation:

- catalog fields live in `src/product.rs`
- capability types and resolver logic live in `src/capabilities.rs`

Avoid placing session-specific probing logic in `libboss-core`.

### Rust: `libboss-session`

Responsibilities:

- bootstrap and protocol probing
- feature-oriented session operations
- capability derivation from observed protocol support
- feature snapshots and update reducers

Current internal module split:

- `bootstrap.rs`
  Device identity and raw protocol support.
- `capability_resolver.rs`
  Product family + function block + probe result -> Boss capability model.
- `settings_session.rs`
  Standby timer, wear detection, auto-aware, auto-play-pause, auto-answer, volume control.
- `audio_modes_session.rs`
  Current mode, mode settings, favorites, prompts, custom profiles.
- `equalizer_session.rs`
  Equalizer reads/writes and verification.
- `workspace.rs`
  Feature workspace/update reducers.

The public `BossSession` type remains source-compatible while delegating feature logic through narrower module-owned impl blocks.

### Swift: `libboss-apple`

Responsibilities:

- public Swift mirrors of identity and capability models
- FFI conversion
- Apple transport and retry policy
- capability-aware session surface

Implemented public types:

- `BossAppleDeviceCapabilities`
- `BossAppleSettingsCapabilities`
- `BossAppleAudioModeCapabilities`
- `BossAppleSoundCapabilities`

Suggested API direction:

- `bootstrap()` returns identity plus capabilities
- workspace loading returns optional feature workspaces
- feature reads and writes check capability state before attempting transport calls where possible

### Swift: `boss-apple-app`

Responsibilities:

- capability-driven presentation logic
- view-model state transitions
- user-facing fallback messaging

Refactor target:

The app should stop assuming every device exposes audio modes. It should render:

- a device settings screen when settings exist
- an audio modes section only when audio mode capabilities exist
- an equalizer section only when equalizer is exposed

### Swift: `bossctl`

Responsibilities:

- capability-aware command behavior
- clear unsupported-setting messaging

Refactor target:

The CLI should inspect capabilities early so unsupported commands fail with precise messages rather than transport-level ambiguity.

## Capability Resolution Strategy

This is the key design choice.

Capability resolution should use three inputs:

1. Product identity
2. Raw protocol support from bootstrap and probing
3. Observed read/write results where needed

It should not rely on product ID alone for full behavior.

### Why product ID alone is not enough

Without hardware, product-based assumptions are too brittle. Two products in the same family may:

- expose different function blocks
- require different write verification behavior
- support only subsets of the same settings

### Why function blocks alone are not enough

A function block may exist while a specific function or operator is unsupported. Boss already sees distinctions like:

- function unsupported
- operator unsupported
- insecure transport
- data unavailable

Those distinctions need to survive into the capability model.

### Recommended rule

Use product family as a hint, not as the sole authority.

Priority order:

1. Explicit observed session support
2. Raw function-block and probe evidence
3. Product-family defaults
4. Unknown capability when evidence is weak

This is safer for QC45 and future devices without direct hardware access.

Practical consequence from the first QC Ultra 2 pass:

- bootstrap must not fail hard if a known product rejects an optional capability-discovery probe such as `ProductInfoAllFblocks`
- workspace loading must degrade optional sections when follow-up reads return function/operator unsupported, rather than failing the whole connect flow

## Migration Phases

### Phase 1: Introduce Shared Capability Types

Add capability model types to Rust and Swift without changing the current public behavior.

Deliverables:

- [x] product family/category fields in catalog types
- [x] new capability types in `libboss-core`
- [x] Swift mirror types in `libboss-apple`

Acceptance criteria:

- [x] no behavioral change yet
- [x] existing tests continue to pass
- [x] new types can be constructed in tests

### Phase 2: Separate Bootstrap Identity From Capability Resolution

Refactor bootstrap so it returns raw identity and raw protocol support, then derives capabilities in a dedicated resolver.

Deliverables:

- [x] raw protocol support model
- [x] capability resolver logic in `libboss-core`
- [x] `BootstrappedDevice` expanded to include derived capabilities

Acceptance criteria:

- [x] product lookup remains stable
- [x] capability derivation is covered by unit tests
- [x] no UI changes required yet
- [x] known-product bootstrap can fall back to catalog-implied protocol support when bounded probes are unsupported

### Phase 3: Split `BossSession` Internals By Feature Area

Move large feature clusters out of `boss_session.rs` into narrower modules.

Deliverables:

- [x] settings-focused internal module
- [x] audio-mode-focused internal module
- [x] equalizer-focused internal module
- [x] workspace module

Acceptance criteria:

- [x] public API remains source-compatible where practical
- [x] feature logic becomes independently testable
- [x] product-specific quirks are easier to isolate

### Phase 4: Make Workspace Loading Capability-Aware

Refactor workspace loading so optional features do not break the entire session.

Deliverables:

- [x] optional audio mode workspace
- [x] optional equalizer snapshot
- [x] settings workspace independent from audio modes

Acceptance criteria:

- [x] a device can connect and load partial state without audio mode support
- [x] unsupported feature paths return structured nil/unavailable states
- [x] unsupported optional feature reads do not abort the entire workspace load

### Phase 5: Refactor `BossAppSessioning` and App State

Update app protocols and view-model flows to depend on capabilities and optional feature workspaces.

Deliverables:

- [ ] `BossAppSessioning` no longer encodes Ultra-specific assumptions
- [x] lifecycle loading paths use capabilities
- [x] UI sections are gated by feature presence

Acceptance criteria:

- [x] mock and fake sessions can represent non-Ultra devices
- [x] the app no longer requires audio modes to consider a device usable

### Phase 6: Refactor Presentation Assets

Move macOS device image resolution onto a product-family or asset-registry model.

Deliverables:

- [x] generic fallback device imagery
- [x] family/variant-based asset mapping

Acceptance criteria:

- [x] non-Ultra devices render without product-name hardcoding
- [x] missing assets do not break the UI

### Phase 7: Add QC45 Catalog and Capability Rules

Only after the architecture above is in place, add QC45 identity and capability mapping.

Deliverables:

- [ ] QC45 product entry in Rust and Swift catalogs
- [ ] QC45 capability defaults and probes
- [ ] fixture-backed tests for degraded/unsupported flows

Acceptance criteria:

- [ ] QC45 can bootstrap as a known product
- [ ] supported features are exposed normally
- [ ] unsupported features degrade cleanly in session, CLI, and app state

## Testing Plan For The Refactor

Because QC45 hardware is unavailable, testing needs to move up one layer from “real-device validation” to “contract validation from synthetic protocol inputs.”

### Rust tests

Add tests for:

- [x] product catalog lookup including family/category
- [x] capability resolver output for known product and protocol-support combinations
- [ ] workspace assembly with missing audio modes
- [ ] workspace assembly with missing equalizer
- [ ] unsupported setting classification from representative BMAP errors

Suggested files:

- `packages/core/libboss/libboss-core/tests/product_catalog.rs`
- `packages/core/libboss/libboss-core/tests/capability_resolution.rs`
- `packages/core/libboss/libboss-session/src/tests.rs`
  Extend existing tests with capability-aware bootstrap and partial-workspace cases.

### Swift bridge tests

Add tests for:

- [x] FFI conversion of capability models
- [x] workspace conversion with optional audio mode/equalizer sections
- [ ] unsupported and unavailable error mapping
- [x] session behavior when capability-gated reads are absent

Suggested files:

- `packages/core/libboss-apple/Tests/libbossAppleTests/BossRustSessionBridgeConversionTests.swift`
- `packages/core/libboss-apple/Tests/libbossAppleTests/BossAppleSessionPublicApiTests.swift`
- `packages/core/libboss-apple/Tests/libbossAppleTests/BossAppleControllerErrorTests.swift`

### App-layer tests

Add tests for:

- [x] successful connection with settings-only workspace
- [ ] successful connection with settings + equalizer but no audio modes
- [ ] successful connection with audio modes but no equalizer
- [ ] hidden or disabled UI actions for unsupported features

Suggested files:

- `packages/ui/apple/app-core/Tests/BossAppleAppTests/BossAppViewModelLifecycleTests.swift`
- `packages/ui/apple/app-core/Tests/BossAppleAppTests/BossAppViewModelModeActionTests.swift`

## Open Design Decisions

### 1. How much capability information should be persisted in public bootstrapped-device types?

Status: resolved for the current implementation.

Recommendation:

Include capabilities in `BootstrappedDevice` or `BossAppleBootstrappedDevice` so downstream layers do not need to repeat derivation logic. Keep raw function blocks too.

### 2. Should unsupported feature reads return `nil`, observed-unavailable states, or throw?

Status: partially implemented.

Recommendation:

- For settings-style reads, prefer structured observed states with an unavailable reason.
- For optional workspace sections, prefer `nil`.
- For mutation requests against unsupported features, fail early with a precise unsupported error.

### 3. Should capability derivation actively probe functions after bootstrap?

Status: still open.

Recommendation:

Yes, but narrowly and only where function-block presence is insufficient. Keep probes deterministic and bounded so connect latency does not balloon.

Examples:

- a safe read to confirm equalizer availability
- a safe read to confirm audio mode capabilities

### 4. Should the app use product family for presentation decisions?

Status: implemented for macOS device artwork; behavior gating still should prefer capabilities.

Recommendation:

Yes for presentation defaults and assets.
No for behavior gating when capability data exists.

## Recommended First Implementation Slice

The best first slice is architectural, not product-specific:

1. [x] Add product family/category fields in Rust and Swift catalog types.
2. [x] Introduce `BossDeviceCapabilities` and Swift mirrors.
3. [x] Refactor bootstrap output to include raw protocol support and derived capabilities.
4. [x] Make workspace loading return optional audio-mode and equalizer sections.
5. [ ] Update `BossAppSessioning` and app lifecycle code to handle those optional sections cleanly.

Current next slice:

1. Finish capability-aware behavior for `BossAppSessioning`, CLI commands, actions, and streams.
2. Add QC45 catalog/capability entries once the expected product ID and supported function behavior are known or fixture-backed.

Only after that should QC45-specific support begin.

## Exit Criteria For This Refactor

The refactor is complete when:

- [x] product identity is no longer the same thing as feature support
- [x] capabilities are explicit in Rust and Swift
- [ ] app and CLI logic depend on capabilities rather than Ultra-only assumptions
- [x] devices with partial support can connect without crashing or failing workspace load
- [x] macOS presentation no longer hardcodes one product name
- [ ] adding a new Bose product requires localized catalog, capability, and test updates rather than a repo-wide rewrite
