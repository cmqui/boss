# bossctl

`bossctl` is the macOS CLI for controlling Bose devices over the Apple BLE transport.

It uses:

- `libboss-apple` for CoreBluetooth transport and typed control APIs
- Rust `libboss` indirectly through the Apple FFI bridge

## Running

Build the Rust FFI once:

```sh
cd ../libboss && cargo build -p libboss-ffi
cd ../bossctl
```

For a shared Homebrew runtime, point `bossctl` at the installed Rust FFI prefix:

```sh
export LIBBOSS_FFI_HOMEBREW_PREFIX="/opt/homebrew/opt/libboss"
```

Then run commands such as:

```sh
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
swift run bossctl audio-mode get settings-config --name Bose
swift run bossctl audio-mode set settings-config --cnc 5 --spatial off --wind-block false --anc-toggle true --name Bose
swift run bossctl audio-mode delete --index 7 --name Bose
swift run bossctl bmap trace --duration 30 --name Bose
swift run bossctl bmap debug-current-mode --duration 30 --name Bose
```

## Notes

- raw `bmap` passthrough commands have been removed
- settings reads prefer snapshot/composite flows where available
- mode-setting and settings writes include verification logic and reconnect handling where needed
- some devices reject specific functions on the unsecure path, so automatic secure fallback is built in where supported

## Further Reading

- [../../docs/bmap-protocol-notes.md](../../docs/bmap-protocol-notes.md) for protocol and BLE transport notes
- [../../docs/current-audio-mode-streaming.md](../../docs/current-audio-mode-streaming.md) for current-audio-mode streaming validation and re-test commands

## Debug Logging

- `LIBBOSS_DEBUG=1` enables Rust `libboss` protocol/session tracing
- `LIBBOSS_FFI_LOG=1` enables Rust FFI loader/runtime logs
- `LIBBOSS_APPLE_DEBUG=1` enables lifecycle and discovery logs
- `LIBBOSS_APPLE_DEBUG_PACKETS=1` additionally logs raw BLE frames
