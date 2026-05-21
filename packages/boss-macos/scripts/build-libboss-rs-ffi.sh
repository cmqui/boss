#!/usr/bin/env bash
set -euo pipefail

# Builds libboss-rs-ffi and, when invoked from Xcode, copies the dylib into the app bundle.
# SRCROOT is packages/boss-macos when run from the Boss Xcode target.

if [[ -f "${HOME}/.cargo/env" ]]; then
  # shellcheck disable=SC1090
  source "${HOME}/.cargo/env"
fi
export PATH="${HOME}/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:${PATH:-/usr/bin:/bin:/usr/sbin:/sbin}"

resolve_cargo() {
  if [[ -n "${CARGO:-}" && -x "${CARGO}" ]]; then
    printf '%s\n' "${CARGO}"
    return 0
  fi
  local candidate
  for candidate in cargo "${HOME}/.cargo/bin/cargo" /opt/homebrew/bin/cargo /usr/local/bin/cargo; do
    if command -v "${candidate}" >/dev/null 2>&1; then
      command -v "${candidate}"
      return 0
    fi
  done
  return 1
}

CARGO_BIN="$(resolve_cargo || true)"
if [[ -z "${CARGO_BIN}" ]]; then
  echo "[build-libboss-rs-ffi] cargo not found in PATH (Xcode builds use a minimal environment)." >&2
  echo "[build-libboss-rs-ffi] Install Rust from https://rustup.rs or set CARGO to the cargo binary path." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
LIBBOSS_RS_DIR="${PACKAGE_DIR}/../libboss-rs"

PROFILE=debug
if [[ "${CONFIGURATION:-Debug}" == "Release" ]]; then
  PROFILE=release
fi

echo "[build-libboss-rs-ffi] Building libboss-rs-ffi (${PROFILE})"
cd "${LIBBOSS_RS_DIR}"
if [[ "${PROFILE}" == "release" ]]; then
  "${CARGO_BIN}" build -p libboss-rs-ffi --release
else
  "${CARGO_BIN}" build -p libboss-rs-ffi
fi

DYLIB="${LIBBOSS_RS_DIR}/target/${PROFILE}/liblibboss_rs_ffi.dylib"
if [[ ! -f "${DYLIB}" ]]; then
  echo "[build-libboss-rs-ffi] Expected dylib at ${DYLIB}" >&2
  exit 1
fi

if [[ -n "${TARGET_BUILD_DIR:-}" && -n "${FRAMEWORKS_FOLDER_PATH:-}" ]]; then
  DEST="${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}"
  mkdir -p "${DEST}"
  cp -f "${DYLIB}" "${DEST}/"
  echo "[build-libboss-rs-ffi] Installed ${DYLIB} -> ${DEST}/"
fi
