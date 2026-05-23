#!/usr/bin/env bash
set -euo pipefail

if [[ -f "${HOME}/.cargo/env" ]]; then
  # shellcheck disable=SC1090
  source "${HOME}/.cargo/env"
fi
export PATH="${HOME}/.cargo/bin:/opt/homebrew/opt/rustup/bin:/opt/homebrew/bin:/usr/local/bin:${PATH:-/usr/bin:/bin:/usr/sbin:/sbin}"

resolve_cargo() {
  if [[ -n "${CARGO:-}" && -x "${CARGO}" ]]; then
    printf '%s\n' "${CARGO}"
    return 0
  fi
  local candidate
  for candidate in "${HOME}/.cargo/bin/cargo" /opt/homebrew/opt/rustup/bin/cargo cargo /opt/homebrew/bin/cargo /usr/local/bin/cargo; do
    if command -v "${candidate}" >/dev/null 2>&1; then
      command -v "${candidate}"
      return 0
    fi
  done
  return 1
}

resolve_rustc() {
  if [[ -n "${RUSTC:-}" && -x "${RUSTC}" ]]; then
    printf '%s\n' "${RUSTC}"
    return 0
  fi
  local candidate
  for candidate in "${HOME}/.cargo/bin/rustc" /opt/homebrew/opt/rustup/bin/rustc rustc /opt/homebrew/bin/rustc /usr/local/bin/rustc; do
    if command -v "${candidate}" >/dev/null 2>&1; then
      command -v "${candidate}"
      return 0
    fi
  done
  return 1
}

usage() {
  cat <<'EOF' >&2
Usage: build-ffi-artifact.sh [--profile debug|release] [--target <rust-target>] [--crate-type staticlib|cdylib] [--copy-to <path>]
EOF
}

PROFILE=debug
TARGET_TRIPLE=""
CRATE_TYPE=staticlib
COPY_TO=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      PROFILE="${2:-}"
      shift 2
      ;;
    --target)
      TARGET_TRIPLE="${2:-}"
      shift 2
      ;;
    --crate-type)
      CRATE_TYPE="${2:-}"
      shift 2
      ;;
    --copy-to)
      COPY_TO="${2:-}"
      shift 2
      ;;
    *)
      usage
      exit 1
      ;;
  esac
done

case "${PROFILE}" in
  debug|release)
    ;;
  *)
    echo "[build-ffi-artifact] Unsupported profile: ${PROFILE}" >&2
    exit 1
    ;;
esac

case "${CRATE_TYPE}" in
  staticlib|cdylib)
    ;;
  *)
    echo "[build-ffi-artifact] Unsupported crate type: ${CRATE_TYPE}" >&2
    exit 1
    ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIBBOSS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CARGO_BIN="$(resolve_cargo || true)"
if [[ -z "${CARGO_BIN}" ]]; then
  echo "[build-ffi-artifact] cargo not found in PATH." >&2
  exit 1
fi

RUSTC_BIN="$(resolve_rustc || true)"
if [[ -z "${RUSTC_BIN}" ]]; then
  echo "[build-ffi-artifact] rustc not found in PATH." >&2
  exit 1
fi
export RUSTC="${RUSTC_BIN}"

BUILD_ARGS=(-p libboss-ffi)
if [[ "${PROFILE}" == "release" ]]; then
  BUILD_ARGS+=(--release)
fi
if [[ -n "${TARGET_TRIPLE}" ]]; then
  BUILD_ARGS+=(--target "${TARGET_TRIPLE}")
fi

echo "[build-ffi-artifact] Building libboss-ffi (${PROFILE}, ${CRATE_TYPE}${TARGET_TRIPLE:+, ${TARGET_TRIPLE}})"
cd "${LIBBOSS_DIR}"
"${CARGO_BIN}" build "${BUILD_ARGS[@]}"

ARTIFACT_DIR="${LIBBOSS_DIR}/target"
if [[ -n "${TARGET_TRIPLE}" ]]; then
  ARTIFACT_DIR+="/${TARGET_TRIPLE}"
fi
ARTIFACT_DIR+="/${PROFILE}"

case "${CRATE_TYPE}" in
  staticlib)
    ARTIFACT_NAME="libboss_ffi.a"
    ;;
  cdylib)
    case "$(uname -s)" in
      Darwin)
        ARTIFACT_NAME="libboss_ffi.dylib"
        ;;
      Linux)
        ARTIFACT_NAME="libboss_ffi.so"
        ;;
      *)
        echo "[build-ffi-artifact] Unsupported host platform for cdylib naming" >&2
        exit 1
        ;;
    esac
    ;;
esac

ARTIFACT_PATH="${ARTIFACT_DIR}/${ARTIFACT_NAME}"
if [[ ! -f "${ARTIFACT_PATH}" ]]; then
  echo "[build-ffi-artifact] Expected artifact at ${ARTIFACT_PATH}" >&2
  exit 1
fi

if [[ -n "${COPY_TO}" ]]; then
  mkdir -p "$(dirname "${COPY_TO}")"
  cp -f "${ARTIFACT_PATH}" "${COPY_TO}"
  echo "[build-ffi-artifact] Copied ${ARTIFACT_PATH} -> ${COPY_TO}"
else
  echo "[build-ffi-artifact] Built ${ARTIFACT_PATH}"
fi
