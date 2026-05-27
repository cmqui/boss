# Rust Stream Multiplexer Implementation Plan

Last reviewed: 2026-05-25

## Goal

Replace the current "one update stream = one packet consumer" model with a shared packet multiplexer so multiple live update streams can coexist safely on one BLE/BMAP session.

This plan is intentionally scoped to the Rust-backed path used by:

- `packages/core/libboss`
- `packages/core/libboss-apple`
- `packages/ui/bossctl`
- `packages/ui/apple/app-core`

It is written to be handed to Codex in a fresh chat.

## Why This Is Needed

The current live-update architecture is structurally unsafe when more than one update stream is active at once.

Today, each Rust FFI update stream created via `boss_update_stream_create(...)` owns its own `FfiLink` and calls `next_packet(...)` independently:

- `packages/core/libboss/libboss-ffi/src/host_link.rs`
- `packages/core/libboss/libboss-ffi/src/update_stream.rs`
- `packages/core/libboss-apple/Sources/libbossApple/BossRustSessionBridge.swift`

That means:

1. multiple logical streams compete for the same underlying BLE packet source
2. one stream can consume packets that another stream needed
3. app-level stream-first designs become unreliable or outright fail

This was already observed in practice:

- the app became unreliable when it subscribed to several dedicated streams at once
- foreground operations and background streams interfered with each other
- mode switching produced `host send callback returned other`

The app has already been narrowed back to a targeted current-mode background check as a workaround. That workaround is acceptable for now, but it is not the desired long-term stream architecture.

## Important Constraint

A multiplexer solves packet-consumer contention. It does **not** invent unsolicited packets that the headset never sends.

Real-device tracing on QC Ultra 2 HP produced:

- only the bootstrap/version packet on the traced link
- no unsolicited `AudioModesCurrentMode` packet when changing modes from the hardware button

Relevant evidence:

- `bossctl bmap trace` was restored on the Rust-backed Apple path
- `docs/bose-bmap-qc-ultra-hp2-analysis.md`

Practical implication:

- a multiplexer is still the correct long-term design
- it should improve concurrent stream correctness and app/CLI architecture
- it may **not** make hardware-button mode changes fully push-driven on this BLE path if the device does not emit an unsolicited packet

Do not oversell the multiplexer as a guaranteed fix for that one device behavior.

## Current State

### What exists now

- typed Rust update streams for:
  - current audio mode
  - audio mode settings
  - equalizer
  - device settings
  - audio mode catalog
- Swift async wrappers over those streams
- `bossctl stream probe ...`
- `bossctl bmap trace ...`

Files:

- `packages/core/libboss/libboss-ffi/src/update_stream.rs`
- `packages/core/libboss-apple/Sources/libbossApple/BossRustSessionBridge.swift`
- `packages/core/libboss-apple/Sources/libbossApple/BossAppleSession.swift`
- `packages/ui/bossctl/Sources/bossctl/StreamCommand.swift`
- `packages/ui/bossctl/Sources/bossctl/BmapCommand.swift`

### Known app-layer workaround currently in place

The app no longer uses the earlier "all typed streams live at once" design. It currently does a narrow hybrid:

- UI-driven changes use direct commands and explicit refresh
- background detection uses a lightweight current-mode check
- full workspace refresh only happens when that single value changes

Files:

- `packages/ui/apple/app-core/Sources/BossAppleApp/BossAppViewModel+Lifecycle.swift`
- `packages/ui/apple/app-core/Sources/BossAppleApp/BossAppSessioning.swift`

This workaround should remain until the multiplexer is proven stable.

## Target Design

Move from:

- many packet consumers
- many independent `next_packet(...)` loops
- typed streams competing for raw traffic

to:

- one packet consumer per active transport/session
- one decoded packet broadcast path
- many logical subscribers fed from that shared packet stream

### Desired ownership split

#### Rust side

Rust should own:

- the shared packet-reader loop
- packet classification/routing
- subscriber registration and fan-out
- stateful reducers for compound streams like device settings and audio mode catalog

#### Swift side

Swift should own:

- BLE transport integration
- connection lifecycle
- async stream adaptation for Apple consumers
- app- and CLI-facing orchestration

This matches the existing migration direction: protocol/session semantics in Rust, host integration in Swift.

## Proposed Architecture

### 1. Introduce a shared update broker in Rust FFI

Instead of creating one `BossFfiUpdateStreamHandle` per independent packet reader, create one shared broker object that:

1. owns a single `FfiLink`
2. runs one packet-read loop
3. decodes every incoming BMAP packet once
4. routes packets to logical subscribers

Possible shape:

- `BossFfiUpdateBrokerHandle`
- internal packet dispatch loop
- subscriber handles for each logical stream kind

Likely files:

- `packages/core/libboss/libboss-ffi/src/update_stream.rs`
- `packages/core/libboss/libboss-ffi/src/host_link.rs`
- possibly a new file such as:
  - `packages/core/libboss/libboss-ffi/src/update_broker.rs`

### 2. Preserve typed stream APIs at the FFI boundary

Do **not** force Swift to consume raw packets directly for normal operation.

Keep the existing logical stream surface if possible:

- current audio mode
- audio mode settings
- equalizer
- device settings
- audio mode catalog

But make those streams subscriber views over one shared packet source.

That means the likely public FFI shape becomes:

- create broker
- create subscriber/stream handle for a specific kind
- `next_*` APIs consume from that subscriber queue, not directly from BLE callbacks

### 3. Add one raw packet subscriber path

The multiplexer should also support a raw packet subscription for diagnostics.

That gives:

- `bossctl bmap trace`
- future protocol debugging
- validation that typed routing is not hiding traffic

This raw subscriber should be a broker output, not a second independent packet reader.

### 4. Make current-mode stream semantics explicit

Current audio mode currently accepts both `Status` and `Result` packets. Keep that behavior.

The new broker should route current-mode updates when packets match:

- function block: `AudioModes`
- function raw: `CURRENT_MODE_FUNCTION_RAW`
- operator: `Status` or `Result`

Do not regress the earlier QC Ultra 2 HP fix.

Relevant file:

- `packages/core/libboss/libboss-ffi/src/update_stream.rs`

### 5. Keep reducer-based streams on top of the broker

Some streams are packet-to-value reducers, not one-packet direct decodes:

- device settings
- audio mode catalog

Those should continue to be reduced on the Rust side, but over the shared broker feed rather than over isolated packet readers.

## Suggested Execution Order

### Phase 1. Refactor Rust FFI internals without changing Swift API yet

Goal:

- keep the current Swift-facing `BossRustSessionBridge` method signatures stable
- swap the underlying FFI implementation from many readers to one shared broker

Tasks:

1. design broker handle and subscriber handle types
2. move packet-read loop behind the broker
3. adapt existing `boss_update_stream_next_*` entrypoints to read from broker-backed subscribers
4. keep tests passing or update them with equivalent coverage

### Phase 2. Add explicit raw packet subscription support

Goal:

- make `bossctl bmap trace` a broker subscriber, not a special parallel link path

Tasks:

1. add raw packet subscriber API in Rust FFI
2. expose it through `libboss-apple`
3. update `bossctl bmap trace` to use the broker path

### Phase 3. Re-enable multi-stream app usage behind a flag or branch

Goal:

- validate that the app can safely subscribe to several typed streams concurrently again

Tasks:

1. restore a stream-first app model on a test branch or guarded path
2. subscribe concurrently to:
   - current audio mode
   - audio mode settings
   - equalizer
   - device settings
   - audio mode catalog
3. verify no transport contention regressions

Do **not** remove the current hybrid app workaround until this passes on hardware.

### Phase 4. Decide final app strategy per data source

After the broker exists, choose per feature:

- pure stream
- stream + targeted read-after-write
- stream + narrow fallback read for external drift

This decision should be based on actual device behavior, not ideology.

## Verification Plan

### Rust/FFI tests

Add coverage for:

1. two or more logical subscribers receiving updates from one raw packet source
2. one subscriber not starving another
3. current mode accepting both `Result` and `Status`
4. device settings reduction still working over the broker
5. audio mode catalog reduction still working over the broker
6. raw packet subscriber seeing the same packets as typed reducers

Likely test location:

- `packages/core/libboss/libboss-ffi/src/tests.rs`

### Swift bridge tests

Add or update tests for:

1. several `BossAppleSession` update streams active simultaneously
2. no stream teardown or send-path failures caused by subscription concurrency
3. typed stream startup/termination behavior remains well-defined

Likely test locations:

- `packages/core/libboss-apple/Tests/libbossAppleTests`
- `packages/ui/apple/app-core/Tests/BossAppleAppTests`

### CLI verification

Use:

- `bossctl stream probe ...`
- `bossctl bmap trace ...`

Desired outcomes:

1. typed probes can run together without starving each other
2. raw trace can run without special transport hacks
3. traced packets explain observed stream behavior

### Hardware verification

Re-run on QC Ultra 2 HP:

1. UI-driven mode changes
2. equalizer changes
3. device setting toggles
4. custom mode catalog changes
5. hardware-button mode changes

Expected interpretation:

- if hardware-button mode changes still emit no unsolicited packet, that is a device/path limitation, not a multiplexer failure

## Non-Goals

This plan does **not** aim to:

- restore the pre-migration broad raw BMAP command surface
- promise pure push-driven hardware-button mode updates on devices that do not emit unsolicited packets
- remove all app-side fallback reads immediately

## Deliverables

Minimum acceptable deliverables:

1. shared broker-based Rust update stream implementation
2. preserved typed stream APIs for Swift consumers
3. raw packet subscription path for diagnostics
4. updated `bossctl bmap trace` on the shared broker path
5. tests proving multiple concurrent logical streams no longer compete for packets

## Handoff Notes For Codex

If you are picking this up in a new chat:

1. Start by reading:
   - `packages/core/libboss/libboss-ffi/src/update_stream.rs`
   - `packages/core/libboss/libboss-ffi/src/host_link.rs`
   - `packages/core/libboss-apple/Sources/libbossApple/BossRustSessionBridge.swift`
   - `packages/core/libboss-apple/Sources/libbossApple/BossAppleSession.swift`
   - `docs/bose-bmap-qc-ultra-hp2-analysis.md`

2. Treat the current app-side hybrid polling workaround as temporary but valid.

3. Do not remove the hybrid fallback until concurrent typed streams are proven stable on hardware.

4. Keep the restored `bossctl bmap trace` command working throughout the refactor. It is now a required diagnostic tool.
