# Boss iOS

SwiftUI iPhone/iPad frontend for controlling Bose devices through `bossAppleApp` and `libbossApple`.

Generate the Xcode project from this package directory:

```sh
./scripts/generate-xcodeproj.sh
```

The iOS target statically links `libboss-ffi`. Before building for device or simulator, install the relevant Rust targets:

```sh
rustup target add aarch64-apple-ios
rustup target add aarch64-apple-ios-sim
```

If you build the simulator from an Intel Mac, also install:

```sh
rustup target add x86_64-apple-ios
```
