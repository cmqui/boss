# Homebrew Packaging

This directory defines the Homebrew distribution contract for the repo.

Tap contract:

- tap name: `cmqui/boss`
- backing GitHub repository: `https://github.com/cmqui/homebrew-boss`
- expected user-facing install commands:
  - `brew tap cmqui/boss`
  - `brew install cmqui/boss/bossctl`
  - `brew install --cask cmqui/boss/boss-ui`
- formula and cask files in this directory are source-of-truth templates for that tap

Distribution set:

- runtime formula: `libboss`
- CLI formula: `bossctl`
- macOS app cask: `boss-ui`

Runtime contract:

- the shared runtime artifact is `libboss_ffi.dylib`
- the stable installed runtime path is expected to be:
  `$(brew --prefix)/opt/libboss/lib/libboss_ffi.dylib`
- Homebrew wrappers or launch scripts should set:
  `LIBBOSS_FFI_HOMEBREW_PREFIX=$(brew --prefix)/opt/libboss`
- `boss-ui` also recognizes the standard Homebrew `opt/libboss` paths directly, so the cask app no longer needs a launcher wrapper just to find the shared runtime

Compatibility contract:

- `libboss`, `bossctl`, and `boss-ui` should be released in lockstep from the same repo version
- the CLI and app should be validated against the exact `libboss` runtime release they depend on

Release artifact contract:

- `libboss` should publish split per-architecture macOS archives, one for `arm64` and one for `x86_64`
- `bossctl` should publish split per-architecture macOS archives, one for `arm64` and one for `x86_64`
- `boss-ui` should publish one universal macOS app archive
- recommended artifact names:
  - `libboss-<version>-macos-arm64.tar.gz`
  - `libboss-<version>-macos-x86_64.tar.gz`
  - `bossctl-<version>-macos-arm64.tar.gz`
  - `bossctl-<version>-macos-x86_64.tar.gz`
  - `boss-ui-<version>-macos-universal.zip`

Status:

- the repo now provides concrete staging targets and output layouts for the Homebrew channel:
  - `make homebrew-stage-runtime` -> `packaging/homebrew/staging/libboss/lib/libboss_ffi.dylib`
  - `make homebrew-stage-bossctl` -> `packaging/homebrew/staging/bossctl/bin/bossctl`
  - `make homebrew-stage-boss-ui` -> `packaging/homebrew/staging/boss-ui/Boss.app`
- the repo now also provides release-oriented per-arch staging and archive targets:
  - `make homebrew-stage-release`
  - `make homebrew-archive-release RELEASE_VERSION=<version>`
  - `make homebrew-archive-release-notarized RELEASE_VERSION=<version>`
- the staged `Boss.app` removes its embedded `libboss_ffi.dylib` and keeps a normal app executable; the shared runtime is resolved through the standard Homebrew `opt/libboss` locations or the explicit env var override
- the release-oriented staging flow now produces:
  - `packaging/homebrew/staging/libboss/arm64/lib/libboss_ffi.dylib`
  - `packaging/homebrew/staging/libboss/x86_64/lib/libboss_ffi.dylib`
  - `packaging/homebrew/staging/bossctl/arm64/bin/bossctl`
  - `packaging/homebrew/staging/bossctl/x86_64/bin/bossctl`
  - `packaging/homebrew/staging/boss-ui/Boss.app`
- the archive flow now produces:
  - `libboss-<version>-macos-arm64.tar.gz`
  - `libboss-<version>-macos-x86_64.tar.gz`
  - `bossctl-<version>-macos-arm64.tar.gz`
  - `bossctl-<version>-macos-x86_64.tar.gz`
  - `boss-ui-<version>-macos-universal.zip`
- notarized `boss-ui` release archives require:
  - `BOSS_MACOS_DEVELOPER_IDENTITY`
    Example: `Developer ID Application: Your Name (TEAMID)`
  - `BOSS_MACOS_NOTARY_KEYCHAIN_PROFILE`
    Create once with `xcrun notarytool store-credentials <profile-name> ...`
- `make homebrew-archive-release-notarized` fails fast if those notarization inputs are missing
- the checked-in formulae and cask still need real release URLs, checksums, and publication-time artifact wiring before they can be used in a tap
- the checked-in formulae and cask now assume GitHub Releases hosted from `cmqui/boss`; publication still requires replacing the placeholder `sha256` values and copying or syncing the files into the `cmqui/homebrew-boss` tap repository
