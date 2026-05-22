# Boss

SwiftUI macOS control surface for Bose devices, currently focused on QC Ultra 2 HP.

Run it from this package directory:

```sh
cd ../libboss && cargo build -p libboss-ffi
cd ../boss-macos && swift run Boss
```

The macOS app supports both Rust FFI modes:

- `Boss` scheme: runtime-loaded `liblibboss_ffi.dylib`
- `Boss Static` scheme: force-loads `liblibboss_ffi.a` into the app binary

The Xcode project runs `scripts/build-libboss-ffi.sh` before each build to compile Rust. Dynamic builds also copy the dylib into `Boss.app/Contents/Frameworks`. Install [Rust](https://rustup.rs) so `cargo` is available (`~/.cargo/bin`); Xcode does not load your shell profile by default.

If you run outside Xcode without embedding the dylib, point at a built copy explicitly:

```sh
export LIBBOSS_FFI_DYLIB="$PWD/../libboss/target/debug/liblibboss_ffi.dylib"
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
- reading and updating selected device settings through the same typed Apple API layer

Behavior notes for Bose QC Ultra 2 HP:

- the Bose UI representation of CNC is inverted relative to the raw BMAP value
- saved custom profile edits follow Bose-style `AudioModes.ModeConfig` writes rather than live `SettingsConfig` writes
- when Wind Block is enabled, firmware normalizes saved-profile CNC to the Bose-displayed maximum (`10`)
