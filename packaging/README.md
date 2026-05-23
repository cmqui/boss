# Packaging

This directory contains distribution-specific packaging metadata and release artifacts.

Guidelines:

- Keep package-manager-facing definitions here.
- Keep build orchestration in the repo-level `Makefile` and thin helper scripts.
- Prefer one subdirectory per distribution channel so future Linux packaging work does not collide with Homebrew-specific files.

Current layout:

- `homebrew/`: Homebrew formulae, casks, and channel-specific docs
- `linux/`: reserved for future Linux package-manager work such as `deb`, `rpm`, or `arch`
- `shared/`: cross-channel release/versioning notes that apply to multiple packaging systems

Build and staging policy:

- Treat `packaging/` as packaging metadata plus staged release inputs, not as the main build system.
- Use the repo-level `Makefile` to produce staging outputs for each channel.
- Keep distribution-specific wrapper logic with the relevant channel under `packaging/<channel>/scripts/`.
