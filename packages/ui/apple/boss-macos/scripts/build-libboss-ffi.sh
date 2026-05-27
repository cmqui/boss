#!/usr/bin/env bash
set -euo pipefail

# Builds libboss-ffi for the active configuration and optionally installs the
# dylib into the app bundle for runtime-loaded builds.
# SRCROOT is packages/ui/apple/boss-macos when run from the Boss Xcode target.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
LIBBOSS_DIR="${PACKAGE_DIR}/../../../core/libboss"
BUILD_SCRIPT="${LIBBOSS_DIR}/scripts/build-ffi-artifact.sh"

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

if [[ ! -x "${BUILD_SCRIPT}" ]]; then
  echo "[build-libboss-ffi] Expected helper at ${BUILD_SCRIPT}" >&2
  exit 1
fi

DYLIB="${LIBBOSS_DIR}/target/${PROFILE}/libboss_ffi.dylib"
STATICLIB="${LIBBOSS_DIR}/target/${PROFILE}/libboss_ffi.a"

if [[ "${LINKAGE}" == "dynamic" ]]; then
  "${BUILD_SCRIPT}" --profile "${PROFILE}" --crate-type cdylib
else
  "${BUILD_SCRIPT}" --profile "${PROFILE}" --crate-type staticlib
fi

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
