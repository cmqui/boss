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
