# Current Audio Mode Streaming Notes

This document records observed behavior for current-audio-mode streaming on Bose hardware tested with `libboss-apple` and `bossctl` in May 2026.

## Summary

`currentAudioModeUpdateStream()` exists and can surface `audioModes.currentMode` packets when the device sends them, but it was not reliable enough in testing to replace polling for hardware-side mode changes.

## Observed Behavior

- the stream reliably yields the seeded initial read
- some devices or firmware may emit an early `audioModes.currentMode` packet during startup
- later hardware-side mode changes were not consistently accompanied by unsolicited BMAP packets in the test window
- `audioModeSettingsUpdateStream()` did not provide a dependable substitute for detecting those mode changes

From `bossctl` validation on the same hardware:

- `swift run bossctl stream probe current-audio-mode --duration 30 --name Bose` produced the seeded initial value and only occasionally one additional update if the hardware mode changed very early after startup
- `swift run bossctl stream probe audio-mode-settings --duration 30 --name Bose` only produced the initial settings snapshot
- `swift run bossctl bmap trace --duration 30 --name Bose` showed startup traffic only in the tested window
- `swift run bossctl bmap debug-current-mode --duration 30 --name Bose` aligned the typed stream with a single startup `audioModes.currentMode` packet and no later raw packets during hardware-side mode changes

## Guidance

- treat `currentAudioModeUpdateStream()` as an opportunistic fast path
- keep polling as the authoritative reconciliation path for current audio mode
- if firmware behavior changes in the future, revalidate before removing polling logic

## Revalidation Commands

```sh
swift run bossctl stream probe current-audio-mode --duration 30 --name Bose
swift run bossctl stream probe audio-mode-settings --duration 30 --name Bose
swift run bossctl bmap trace --duration 30 --name Bose
swift run bossctl bmap debug-current-mode --duration 30 --name Bose
```

Also try `--characteristic secure` and `--characteristic unsecure` to rule out characteristic-specific notification behavior.
