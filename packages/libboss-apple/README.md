# libboss-apple

`libboss-apple` provides the Apple/CoreBluetooth transport layer for [`libboss`](../libboss/README.md).

Current scope:

- `CoreBluetooth` central connection flow for Bose BLE peripherals
- Bose BMAP service and characteristic discovery
- ATT-MTU-aware BLE writes
- notification ingestion into `libboss` transport frames
- executable bootstrap runner for live hardware validation
- executable `bossctl` prototype for raw BMAP interrogation

Observed Bose QC Ultra 2 HP behavior on macOS:

- service UUID: `0000FEBE-0000-1000-8000-00805F9B34FB`
- unsecure characteristic: `D417C028-9818-4354-99D1-2AC09D074591`
- secure characteristic: `C65B8F2F-AEE2-4C89-B758-BC4892D6F2D8`
- bootstrap writes should target the unsecure characteristic
- bootstrap notifications arrive on the secure characteristic
- `writeWithoutResponse` is the working write mode on real hardware

## Running

```bash
cd packages/libboss-apple
swift run boss-bootstrap --name Bose --timeout 20
```

Useful options:

- `--identifier <uuid>` to target a specific peripheral
- `--characteristic automatic|unsecure|secure` to override write-characteristic preference
- `--timeout <seconds>` to adjust scan timeout

## Raw BMAP CLI

```bash
swift run bossctl bootstrap --name Bose
swift run bossctl settings get standby-timer --name Bose
swift run bossctl settings set standby-timer --minutes 20 --name Bose
swift run bossctl settings get auto-aware --name Bose
swift run bossctl settings set auto-aware --enabled true --name Bose
swift run bossctl settings get on-head-detection --name Bose
swift run bossctl settings get volume-control --name Bose
swift run bossctl settings set volume-control --mode captouch --name Bose
swift run bossctl audio-mode list --name Bose
swift run bossctl audio-mode get current --name Bose
swift run bossctl audio-mode set current --index 1 --name Bose
swift run bossctl audio-mode set current --mode Quiet --name Bose
swift run bossctl bmap watch --name Bose --count 5
swift run bossctl bmap send --name Bose --block 0x00 --function 0x01 --op get
```

`bossctl bmap send` accepts raw block/function/operator values so you can probe settings and status functions before adding typed APIs.

Current behavior notes:

- `bossctl settings get ...` now resolves from a single `SettingsGetAll` snapshot instead of issuing per-setting reads.
- `bossctl settings set ...` still sends the direct `SetGet` packet for that function.
- `bossctl audio-mode list` uses `AudioModesModeConfig Start` and collects streamed mode-config `status` packets until `result`.
- `bossctl audio-mode list` hides empty user-configurable placeholder slots.
- `bossctl audio-mode get current` uses a direct `AudioModesCurrentMode Get`.
- `bossctl audio-mode set current` accepts either `--index <n>` or `--mode <name>` and uses `AudioModesCurrentMode Start` with `modeIndex` plus `playVoicePrompt`.
- on Bose QC Ultra 2 HP, the direct `AudioModesCurrentMode Start` response is the most trustworthy success signal for mode changes.
- on macOS/CoreBluetooth, immediate post-write `AudioModesCurrentMode Get` verification is not fully reliable; `bossctl` treats readback as best-effort and may report `verification inconclusive` instead of a false failure.
- on Bose QC Ultra 2 HP, `auto-play-pause` reads cleanly from standalone settings function `0x18`.
- on Bose QC Ultra 2 HP, `auto-answer` writes through standalone settings function `0x1B`, but reads may need to fall back to the `on-head-detection` composite payload (`0x10`) when `0x1B` is absent from the snapshot.
- some settings requests on QC Ultra 2 HP reject the unsecure path with BMAP error `0x14` (`InsecureTransport`), so `bossctl settings ...` now retries over the secure characteristic automatically when `--characteristic automatic` is used.
- if a command fails, `bossctl` now prints the raw BMAP error payload so capability or semantics mismatches are visible instead of collapsing everything into a generic error.

Debug logging:

- `LIBBOSS_APPLE_DEBUG=1` enables lifecycle and discovery logs
- `LIBBOSS_APPLE_DEBUG_PACKETS=1` additionally logs raw BLE write/notification frames

Example:

```bash
LIBBOSS_APPLE_DEBUG=1 LIBBOSS_APPLE_DEBUG_PACKETS=1 \
  swift run boss-bootstrap --name Bose --timeout 20
```
