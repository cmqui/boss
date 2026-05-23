#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:-}"
if [[ -z "${APP_PATH}" ]]; then
  echo "usage: prepare-boss-ui.sh /path/to/Boss.app" >&2
  exit 1
fi

CONTENTS_DIR="${APP_PATH}/Contents"
FRAMEWORKS_DIR="${CONTENTS_DIR}/Frameworks"
EMBEDDED_DYLIB_PATH="${FRAMEWORKS_DIR}/libboss_ffi.dylib"

rm -f "${EMBEDDED_DYLIB_PATH}"
codesign --force --deep --sign - --timestamp=none "${APP_PATH}"
