# Multi-Device Refactor Plan

Last reviewed: 2026-05-24

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

## Current Problems

### 1. Product identity and product behavior are mixed together

Current product recognition is a small catalog lookup:

- [packages/libboss/libboss-core/src/product.rs](/Users/ciara/Code/boss/packages/libboss/libboss-core/src/product.rs:1)
- [packages/libboss-apple/Sources/libbossApple/BossApplePublicTypes.swift](/Users/ciara/Code/boss/packages/libboss-apple/Sources/libbossApple/BossApplePublicTypes.swift:1)

But the rest of the stack assumes a single high-feature headphone shape. That means product support is not actually driven by catalog data.

### 2. Capability inference is too implicit

`BootstrappedDevice` exposes raw product metadata and function blocks, but there is no first-class capability model that says which Boss features are:

- supported
- writable
- observable
- transport-limited
- unavailable on this session

This logic is instead scattered through session reads, write fallbacks, and UI assumptions.

### 3. `BossSession` is organized around one “fully featured” device model

The Rust session surface in [boss_session.rs](/Users/ciara/Code/boss/packages/libboss/libboss-session/src/boss_session.rs:1) treats audio modes, custom profiles, favorites, equalizer, and device settings as one canonical feature set. That works for Ultra-style devices, but it is the wrong default for a multi-device library.

### 4. The Apple bridge and app layer assume audio modes are central

The current workspace load path:

- [packages/libboss-apple/Sources/libbossApple/BossAppleSession.swift](/Users/ciara/Code/boss/packages/libboss-apple/Sources/libbossApple/BossAppleSession.swift:130)
- [packages/boss-apple-app/Sources/BossAppleApp/BossAppViewModel+Lifecycle.swift](/Users/ciara/Code/boss/packages/boss-apple-app/Sources/BossAppleApp/BossAppViewModel+Lifecycle.swift:81)

assumes that a connected device loads:

- a mode workspace
- audio mode catalog
- optional equalizer inside that mode workspace

That model is too specific. Some devices will have settings without editable audio modes. Others may have different write paths or partial support.

### 5. Product-specific presentation is hardcoded

The macOS asset resolver currently keys directly on the Ultra product name:

- [packages/boss-macos/Sources/BossMacOS/BossResources.swift](/Users/ciara/Code/boss/packages/boss-macos/Sources/BossMacOS/BossResources.swift:28)

This is manageable for one device family but not for a growing product catalog.

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

Boss needs a first-class capability model for its own feature set. This is the main missing abstraction today.

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

The current workspace model is too mode-centric. Replace it with composable feature snapshots.

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

Suggested additions:

- `src/catalog.rs` or expand `src/product.rs`
- `src/capabilities.rs`

Avoid placing session-specific probing logic in `libboss-core`.

### Rust: `libboss-session`

Responsibilities:

- bootstrap and protocol probing
- feature-oriented session operations
- capability derivation from observed protocol support
- feature snapshots and update reducers

Suggested internal module split:

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
  Assembly of feature workspaces based on capabilities.

The public `BossSession` type can remain for now, but should delegate into narrower feature modules instead of containing all logic directly.

### Swift: `libboss-apple`

Responsibilities:

- public Swift mirrors of identity and capability models
- FFI conversion
- Apple transport and retry policy
- capability-aware session surface

Suggested additions:

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

## Migration Phases

### Phase 1: Introduce Shared Capability Types

Add capability model types to Rust and Swift without changing the current public behavior.

Deliverables:

- product family/category fields in catalog types
- new capability types in `libboss-core`
- Swift mirror types in `libboss-apple`

Acceptance criteria:

- no behavioral change yet
- existing tests continue to pass
- new types can be constructed in tests

### Phase 2: Separate Bootstrap Identity From Capability Resolution

Refactor bootstrap so it returns raw identity and raw protocol support, then derives capabilities in a dedicated resolver.

Deliverables:

- raw protocol support model
- capability resolver module
- `BootstrappedDevice` expanded or split to include derived capabilities

Acceptance criteria:

- product lookup remains stable
- capability derivation is covered by unit tests
- no UI changes required yet

### Phase 3: Split `BossSession` Internals By Feature Area

Move large feature clusters out of `boss_session.rs` into narrower modules.

Deliverables:

- settings-focused internal module
- audio-mode-focused internal module
- equalizer-focused internal module
- workspace assembly module

Acceptance criteria:

- public API remains source-compatible where practical
- feature logic becomes independently testable
- product-specific quirks are easier to isolate

### Phase 4: Make Workspace Loading Capability-Aware

Refactor workspace loading so optional features do not break the entire session.

Deliverables:

- optional audio mode workspace
- optional equalizer snapshot
- settings workspace independent from audio modes

Acceptance criteria:

- a device can connect and load partial state without audio mode support
- unsupported feature paths return structured nil/unavailable states

### Phase 5: Refactor `BossAppSessioning` and App State

Update app protocols and view-model flows to depend on capabilities and optional feature workspaces.

Deliverables:

- `BossAppSessioning` no longer encodes Ultra-specific assumptions
- lifecycle loading paths use capabilities
- UI sections are gated by feature presence

Acceptance criteria:

- mock and fake sessions can represent non-Ultra devices
- the app no longer requires audio modes to consider a device usable

### Phase 6: Refactor Presentation Assets

Move macOS device image resolution onto a product-family or asset-registry model.

Deliverables:

- generic fallback device imagery
- family/variant-based asset mapping

Acceptance criteria:

- non-Ultra devices render without product-name hardcoding
- missing assets do not break the UI

### Phase 7: Add QC45 Catalog and Capability Rules

Only after the architecture above is in place, add QC45 identity and capability mapping.

Deliverables:

- QC45 product entry in Rust and Swift catalogs
- QC45 capability defaults and probes
- fixture-backed tests for degraded/unsupported flows

Acceptance criteria:

- QC45 can bootstrap as a known product
- supported features are exposed normally
- unsupported features degrade cleanly in session, CLI, and app state

## Testing Plan For The Refactor

Because QC45 hardware is unavailable, testing needs to move up one layer from “real-device validation” to “contract validation from synthetic protocol inputs.”

### Rust tests

Add tests for:

- product catalog lookup including family/category
- capability resolver output for known product and protocol-support combinations
- workspace assembly with missing audio modes
- workspace assembly with missing equalizer
- unsupported setting classification from representative BMAP errors

Suggested files:

- `packages/libboss/libboss-core/tests/product_catalog.rs`
- `packages/libboss/libboss-core/tests/capability_resolution.rs`
- `packages/libboss/libboss-session/src/tests.rs`
  Extend existing tests with capability-aware bootstrap and partial-workspace cases.

### Swift bridge tests

Add tests for:

- FFI conversion of capability models
- workspace conversion with optional audio mode/equalizer sections
- unsupported and unavailable error mapping
- session behavior when capability-gated reads are absent

Suggested files:

- `packages/libboss-apple/Tests/libbossAppleTests/BossRustSessionBridgeConversionTests.swift`
- `packages/libboss-apple/Tests/libbossAppleTests/BossAppleSessionPublicApiTests.swift`
- `packages/libboss-apple/Tests/libbossAppleTests/BossAppleControllerErrorTests.swift`

### App-layer tests

Add tests for:

- successful connection with settings-only workspace
- successful connection with settings + equalizer but no audio modes
- successful connection with audio modes but no equalizer
- hidden or disabled UI actions for unsupported features

Suggested files:

- `packages/boss-apple-app/Tests/BossAppleAppTests/BossAppViewModelLifecycleTests.swift`
- `packages/boss-apple-app/Tests/BossAppleAppTests/BossAppViewModelModeActionTests.swift`

## Open Design Decisions

### 1. How much capability information should be persisted in public bootstrapped-device types?

Recommendation:

Include capabilities in `BootstrappedDevice` or `BossAppleBootstrappedDevice` so downstream layers do not need to repeat derivation logic. Keep raw function blocks too.

### 2. Should unsupported feature reads return `nil`, observed-unavailable states, or throw?

Recommendation:

- For settings-style reads, prefer structured observed states with an unavailable reason.
- For optional workspace sections, prefer `nil`.
- For mutation requests against unsupported features, fail early with a precise unsupported error.

### 3. Should capability derivation actively probe functions after bootstrap?

Recommendation:

Yes, but narrowly and only where function-block presence is insufficient. Keep probes deterministic and bounded so connect latency does not balloon.

Examples:

- a safe read to confirm equalizer availability
- a safe read to confirm audio mode capabilities

### 4. Should the app use product family for presentation decisions?

Recommendation:

Yes for presentation defaults and assets.
No for behavior gating when capability data exists.

## Recommended First Implementation Slice

The best first slice is architectural, not product-specific:

1. Add product family/category fields in Rust and Swift catalog types.
2. Introduce `BossDeviceCapabilities` and Swift mirrors.
3. Refactor bootstrap output to include raw protocol support and derived capabilities.
4. Make workspace loading return optional audio-mode and equalizer sections.
5. Update `BossAppSessioning` and app lifecycle code to handle those optional sections cleanly.

Only after that should QC45-specific support begin.

## Exit Criteria For This Refactor

The refactor is complete when:

- product identity is no longer the same thing as feature support
- capabilities are explicit in Rust and Swift
- app and CLI logic depend on capabilities rather than Ultra-only assumptions
- devices with partial support can connect without crashing or failing workspace load
- macOS presentation no longer hardcodes one product name
- adding a new Bose product requires localized catalog, capability, and test updates rather than a repo-wide rewrite
