#!/usr/bin/env bash
set -euo pipefail

# Builds libboss-ffi for the active configuration and optionally installs the
# dylib into the app bundle for runtime-loaded builds.
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
  echo "[build-libboss-ffi] cargo not found in PATH (Xcode builds use a minimal environment)." >&2
  echo "[build-libboss-ffi] Install Rust from https://rustup.rs or set CARGO to the cargo binary path." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
LIBBOSS_DIR="${PACKAGE_DIR}/../libboss"

PROFILE=debug
if [[ "${CONFIGURATION:-Debug}" == Release* ]]; then
  PROFILE=release
fi

ACTION="${1:-build}"
LINKAGE="${BOSS_RUST_FFI_LINKAGE:-dynamic}"

case "${ACTION}" in
  build|install)
    ;;
  *)
    echo "[build-libboss-ffi] Unsupported action: ${ACTION}" >&2
    exit 1
    ;;
esac

case "${LINKAGE}" in
  dynamic|static)
    ;;
  *)
    echo "[build-libboss-ffi] Unsupported linkage mode: ${LINKAGE}" >&2
    exit 1
    ;;
esac

echo "[build-libboss-ffi] Building libboss-ffi (${PROFILE}, ${LINKAGE})"
cd "${LIBBOSS_DIR}"
if [[ "${PROFILE}" == "release" ]]; then
  "${CARGO_BIN}" build -p libboss-ffi --release
else
  "${CARGO_BIN}" build -p libboss-ffi
fi

DYLIB="${LIBBOSS_DIR}/target/${PROFILE}/liblibboss_ffi.dylib"
STATICLIB="${LIBBOSS_DIR}/target/${PROFILE}/liblibboss_ffi.a"

if [[ "${LINKAGE}" == "dynamic" && ! -f "${DYLIB}" ]]; then
  echo "[build-libboss-ffi] Expected dylib at ${DYLIB}" >&2
  exit 1
fi

if [[ "${LINKAGE}" == "static" && ! -f "${STATICLIB}" ]]; then
  echo "[build-libboss-ffi] Expected static library at ${STATICLIB}" >&2
  exit 1
fi

if [[ "${ACTION}" == "install" && "${LINKAGE}" == "static" ]]; then
  echo "[build-libboss-ffi] Static linkage selected; skipping dylib install"
  exit 0
fi

if [[ "${ACTION}" == "install" && -n "${TARGET_BUILD_DIR:-}" && -n "${FRAMEWORKS_FOLDER_PATH:-}" ]]; then
  DEST="${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}"
  mkdir -p "${DEST}"
  cp -f "${DYLIB}" "${DEST}/"
  echo "[build-libboss-ffi] Installed ${DYLIB} -> ${DEST}/"
fi
