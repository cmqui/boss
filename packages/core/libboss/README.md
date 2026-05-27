# libboss

`libboss` is the Rust source of truth for portable BMAP protocol, parsing, and session logic.

Workspace crates:

- `libboss-core`: protocol types, codecs, parsers, and portable value models
- `libboss-session`: transport-abstract bootstrap and session helpers
- `libboss-ffi`: C ABI for Swift and other host languages

## Common Commands

Build the FFI dylib:

```sh
cargo build -p libboss-ffi
```

Build a specific FFI artifact with the shared helper:

```sh
./scripts/build-ffi-artifact.sh --profile debug --crate-type cdylib
./scripts/build-ffi-artifact.sh --profile release --target aarch64-apple-ios --crate-type staticlib
```

Run tests:

```sh
cargo test
```

Format the workspace:

```sh
cargo fmt --all
```

## Role In This Repo

- `libboss-apple` uses `libboss-ffi` for protocol/session work
- `bossctl` and `boss-macos` consume the Apple layer, not this workspace directly
- the old Swift implementation lives in [`../../old/libboss`](../../old/libboss/README.md) and is deprecated
