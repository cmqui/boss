# bossctl

`bossctl` is a prototype CLI for controlling Bose BMAP devices over the Apple BLE transport.

It depends on:

- `libboss` for BMAP packets, sessions, and BLE frame handling
- `libbossApple` for CoreBluetooth transport and reusable async control APIs

## Running

```bash
cd packages/bossctl
swift run bossctl bootstrap --name Bose
swift run bossctl settings get standby-timer --name Bose
swift run bossctl settings set standby-timer --minutes 20 --name Bose
swift run bossctl settings get auto-aware --name Bose
swift run bossctl settings set auto-aware --enabled true --name Bose
swift run bossctl settings get on-head-detection --name Bose
swift run bossctl settings set on-head-detection --enabled true --auto-play true --name Bose
swift run bossctl settings get volume-control --name Bose
swift run bossctl settings set volume-control --mode captouch --name Bose
swift run bossctl audio-mode list --name Bose
swift run bossctl audio-mode get current --name Bose
swift run bossctl audio-mode set current --index 1 --name Bose
swift run bossctl audio-mode set current --mode Quiet --name Bose
swift run bossctl audio-mode get settings-config --name Bose
swift run bossctl audio-mode set settings-config --cnc 5 --spatial off --wind-block false --anc-toggle true --name Bose
swift run bossctl audio-mode cnc --level 5 --name Bose
swift run bossctl audio-mode spatial head --name Bose
swift run bossctl audio-mode wind-block false --name Bose
swift run bossctl audio-mode anc true --name Bose
swift run bossctl bmap watch --name Bose --count 5
swift run bossctl bmap send --name Bose --block 0x00 --function 0x01 --op get
```

`bossctl bmap send` accepts raw block/function/operator values so you can probe settings and status functions before adding typed APIs.

## Behavior Notes

- `settings get ...` resolves from a single `SettingsGetAll` snapshot instead of issuing per-setting reads.
- `settings set ...` sends the direct `SetGet` packet for that function.
- `audio-mode list` uses `AudioModesModeConfig Start` and collects streamed mode-config `status` packets until `result`.
- `audio-mode list` hides empty user-configurable placeholder slots.
- `audio-mode get current` uses a direct `AudioModesCurrentMode Get`.
- `audio-mode set current` accepts either `--index <n>` or `--mode <name>` and uses `AudioModesCurrentMode Start` with `modeIndex` plus `playVoicePrompt`.
- `audio-mode get settings-config` reads live AudioModes settings from block `0x1F`, function `0x0A`.
- `audio-mode set settings-config` writes the same live config with `SetGet`; omitted fields are preserved from the current device state.
- `audio-mode set settings-config` verifies the exact target config after writing and reconnects for readback if the BLE stream ends or times out.
- If a settings-config write was sent but verification remains inconclusive after retries, `bossctl` reports that explicitly instead of claiming the update failed or succeeded.
- The live settings-config payload controls CNC level, auto-CNC, spatial audio, wind block, and ANC toggle. CNC is inverted on QC Ultra 2 HP: `0` is maximum ANC and `10` is most ambient.
- `audio-mode cnc|spatial|wind-block|anc` are convenience wrappers over the same verified `settings-config` write path.
- Wrapper commands verify the requested field only; the firmware may normalize related fields, for example disabling ANC can reset CNC to `10`.
- On Bose QC Ultra 2 HP, the direct `AudioModesCurrentMode Start` response is the most trustworthy success signal for mode changes.
- On macOS/CoreBluetooth, immediate post-write `AudioModesCurrentMode Get` verification is not fully reliable; `bossctl` treats readback as best-effort and may report `verification inconclusive` instead of a false failure.
- On Bose QC Ultra 2 HP, `auto-play-pause` reads cleanly from standalone settings function `0x18`.
- On Bose QC Ultra 2 HP, `auto-answer` writes through standalone settings function `0x1B`, but reads may need to fall back to the `on-head-detection` composite payload (`0x10`) when `0x1B` is absent from the snapshot.
- On products where Bose does not expose capability `30527` (`in_place_detection`), the official Android app does not use the composite `on-head-detection` write path. It writes `auto-play-pause` (`0x18`), `auto-answer` (`0x1B`), and `auto-aware` / auto-transparency (`0x1D`) separately instead.
- `bossctl settings set on-head-detection --auto-play ...`, `--auto-answer ...`, and `--auto-transparency ...` now follow that same fallback behavior through `libbossApple`.
- `bossctl settings set on-head-detection --enabled ...` still requires a working composite `0x10` path; if the device rejects that capability, `bossctl` reports the master toggle as unsupported instead of pretending the write should work.
- On QC Ultra 2 HP specifically, the currently observed fallback matrix is:
  - `--auto-play`: supported through `0x18`
  - `--auto-answer`: supported through `0x1B`
  - `--auto-transparency`: unsupported through `0x1D`
  - `--enabled`: unsupported without composite `0x10`
- On Bose QC Ultra 2 HP, `volume-control` has a known Android response type and includes a supported-modes bitmask in its status payload, but the direct Apple/CoreBluetooth read path still currently reports `function unsupported` in many sessions.
- Some settings requests on QC Ultra 2 HP reject the unsecure path with BMAP error `0x14` (`InsecureTransport`), so `bossctl settings ...` retries over the secure characteristic automatically when `--characteristic automatic` is used.
- If a command fails, `bossctl` prints the raw BMAP error payload so capability or semantics mismatches are visible instead of collapsing everything into a generic error.

## Debug Logging

- `LIBBOSS_APPLE_DEBUG=1` enables lifecycle and discovery logs
- `LIBBOSS_APPLE_DEBUG_PACKETS=1` additionally logs raw BLE write/notification frames

Example:

```bash
LIBBOSS_APPLE_DEBUG=1 LIBBOSS_APPLE_DEBUG_PACKETS=1 \
  swift run bossctl audio-mode get settings-config --name Bose
```
