# libboss-rs

`libboss-rs` is the Rust rewrite of the portable `libboss` core.

Current workspace crates:

- `libboss-rs-core`: deterministic BMAP protocol types, codecs, parsers, and portable value models
- `libboss-rs-session`: transport-abstract bootstrap and session helpers
- `libboss-rs-ffi`: C ABI entry points for Swift and other host languages

This is an in-repo migration workspace. The existing Swift `libboss` remains the reference implementation until parity is established.

