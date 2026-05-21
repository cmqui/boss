# Boss

SwiftUI macOS control surface for Bose QC Ultra 2 HP.

Run it from this package directory:

```sh
cd ../libboss-rs && cargo build -p libboss-rs-ffi
cd ../boss-macos && swift run Boss
```

The macOS app loads `liblibboss_rs_ffi.dylib` at runtime. The Xcode project runs `scripts/build-libboss-rs-ffi.sh` after each build and copies the dylib into `Boss.app/Contents/Frameworks`. Install [Rust](https://rustup.rs) so `cargo` is available (`~/.cargo/bin`); Xcode does not load your shell profile by default.

If you run outside Xcode without embedding the dylib, point at a built copy explicitly:

```sh
export LIBBOSS_RS_FFI_DYLIB="$PWD/../libboss-rs/target/debug/liblibboss_rs_ffi.dylib"
swift run Boss
```

Build a release `.app` bundle:

```sh
./scripts/build-release-app.sh
```

The GUI currently uses `BossAppleController` from `libbossApple` and provides a small scaffold for:

- filtering by Bluetooth device name
- loading displayable audio modes
- switching the current audio mode
- reading and applying CNC, spatial audio, Wind Block, and ANC toggle settings

Behavior notes for Bose QC Ultra 2 HP:

- the Bose UI representation of CNC is inverted relative to the raw BMAP value
- saved custom profile edits follow Bose-style `AudioModes.ModeConfig` writes rather than live `SettingsConfig` writes
- when Wind Block is enabled, firmware normalizes saved-profile CNC to the Bose-displayed maximum (`10`)
