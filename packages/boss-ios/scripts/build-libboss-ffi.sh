#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
LIBBOSS_DIR="${PACKAGE_DIR}/../libboss"
BUILD_SCRIPT="${LIBBOSS_DIR}/scripts/build-ffi-artifact.sh"

PROFILE=debug
if [[ "${CONFIGURATION:-Debug}" == Release* ]]; then
  PROFILE=release
fi

SDK_NAME_VALUE="${SDK_NAME:-iphonesimulator}"
CURRENT_ARCH="${NATIVE_ARCH_ACTUAL:-${ARCHS%% *}}"

case "${SDK_NAME_VALUE}" in
  iphoneos*)
    TARGET_TRIPLE="aarch64-apple-ios"
    ;;
  iphonesimulator*)
    if [[ "${CURRENT_ARCH}" == "x86_64" ]]; then
      TARGET_TRIPLE="x86_64-apple-ios"
    else
      TARGET_TRIPLE="aarch64-apple-ios-sim"
    fi
    ;;
  *)
    echo "[build-libboss-ffi-ios] Unsupported SDK_NAME: ${SDK_NAME_VALUE}" >&2
    exit 1
    ;;
esac

DESTINATION="${LIBBOSS_DIR}/target/apple-static/current/liblibboss_ffi.a"

if [[ ! -x "${BUILD_SCRIPT}" ]]; then
  echo "[build-libboss-ffi-ios] Expected helper at ${BUILD_SCRIPT}" >&2
  exit 1
fi

"${BUILD_SCRIPT}" \
  --profile "${PROFILE}" \
  --target "${TARGET_TRIPLE}" \
  --crate-type staticlib \
  --copy-to "${DESTINATION}"
