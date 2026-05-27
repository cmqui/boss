# libboss-OLD

`libboss-OLD` is the deprecated Swift implementation that originally owned BMAP packet parsing, framing, and session logic.

Status:

- kept temporarily as a reference while the Rust `libboss` workspace settles
- not used by `libboss-apple`, `bossctl`, or `boss-macos` anymore
- should not receive new feature work

Notes:

- the Swift module/target name remains `libboss` for archival builds
- the package directory and package name are intentionally marked `-OLD` to discourage new dependencies

Historic scope:

- raw BMAP packet encode/decode
- BLE framing and segmentation
- transport-agnostic bootstrap/session helpers
- typed ProductInfo, Settings, and AudioModes codecs
