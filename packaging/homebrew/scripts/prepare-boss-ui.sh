#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:-}"
if [[ -z "${APP_PATH}" ]]; then
  echo "usage: prepare-boss-ui.sh /path/to/Boss.app" >&2
  exit 1
fi

CONTENTS_DIR="${APP_PATH}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
FRAMEWORKS_DIR="${CONTENTS_DIR}/Frameworks"
EXECUTABLE_NAME="Boss"
REAL_EXECUTABLE_NAME="${EXECUTABLE_NAME}-real"
EXECUTABLE_PATH="${MACOS_DIR}/${EXECUTABLE_NAME}"
REAL_EXECUTABLE_PATH="${MACOS_DIR}/${REAL_EXECUTABLE_NAME}"
EMBEDDED_DYLIB_PATH="${FRAMEWORKS_DIR}/libboss_ffi.dylib"

if [[ ! -f "${EXECUTABLE_PATH}" ]]; then
  echo "[prepare-boss-ui] Expected executable at ${EXECUTABLE_PATH}" >&2
  exit 1
fi

rm -f "${EMBEDDED_DYLIB_PATH}"
mv "${EXECUTABLE_PATH}" "${REAL_EXECUTABLE_PATH}"

cat > "${EXECUTABLE_PATH}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${LIBBOSS_FFI_HOMEBREW_PREFIX:-}" ]]; then
  if [[ -d "/opt/homebrew/opt/libboss" ]]; then
    export LIBBOSS_FFI_HOMEBREW_PREFIX="/opt/homebrew/opt/libboss"
  elif [[ -d "/usr/local/opt/libboss" ]]; then
    export LIBBOSS_FFI_HOMEBREW_PREFIX="/usr/local/opt/libboss"
  fi
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/Boss-real" "$@"
EOF

chmod +x "${EXECUTABLE_PATH}" "${REAL_EXECUTABLE_PATH}"
codesign --force --deep --sign - --timestamp=none "${APP_PATH}"
