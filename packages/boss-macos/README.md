# Boss

SwiftUI macOS control surface for Bose QC Ultra 2 HP.

Run it from this package directory:

```sh
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
