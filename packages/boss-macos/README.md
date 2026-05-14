# boss-macos

SwiftUI macOS control surface for Bose QC Ultra 2 HP.

Run it from this package directory:

```sh
swift run boss-macos
```

The GUI currently uses `BossAppleController` from `libbossApple` and provides a small scaffold for:

- filtering by Bluetooth device name
- loading displayable audio modes
- switching the current audio mode
- reading and applying CNC, spatial audio, Wind Block, and ANC toggle settings

