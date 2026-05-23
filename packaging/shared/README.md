# Shared Packaging Notes

Use this directory for cross-channel release notes, versioning rules, and compatibility guidance that apply to more than one packaging system.

Current policy highlights:

- the shared runtime artifact name is `libboss_ffi.*`
- Homebrew distribution uses a lockstep release set of `libboss`, `bossctl`, and `boss-ui`
- macOS self-contained app releases remain distinct from the shared-runtime Homebrew channel
- for the Homebrew channel, `libboss` and `bossctl` are intended to ship as split per-architecture macOS artifacts, while `boss-ui` ships as a universal macOS app archive
