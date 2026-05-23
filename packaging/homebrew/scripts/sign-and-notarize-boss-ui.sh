#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:-}"
ZIP_PATH="${2:-}"
if [[ -z "${APP_PATH}" || -z "${ZIP_PATH}" ]]; then
  echo "usage: sign-and-notarize-boss-ui.sh /path/to/Boss.app /path/to/boss-ui.zip" >&2
  exit 1
fi

if [[ ! -d "${APP_PATH}" ]]; then
  echo "[sign-and-notarize-boss-ui] Expected app bundle at ${APP_PATH}" >&2
  exit 1
fi

SIGNING_IDENTITY="${BOSS_MACOS_DEVELOPER_IDENTITY:-}"
NOTARY_PROFILE="${BOSS_MACOS_NOTARY_KEYCHAIN_PROFILE:-}"
REQUIRE_NOTARIZATION="${BOSS_MACOS_REQUIRE_NOTARIZATION:-0}"

sign_path() {
  local path="$1"
  shift
  codesign --force --sign "${SIGNING_IDENTITY}" --timestamp "$@" "${path}"
}

is_macho_file() {
  file -b "$1" | grep -q "Mach-O"
}

if [[ -n "${SIGNING_IDENTITY}" ]]; then
  while IFS= read -r -d '' path; do
    if is_macho_file "${path}"; then
      sign_path "${path}"
    fi
  done < <(find "${APP_PATH}/Contents/Frameworks" "${APP_PATH}/Contents/PlugIns" -type f -print0 2>/dev/null || true)

  while IFS= read -r -d '' path; do
    if is_macho_file "${path}"; then
      sign_path "${path}"
    fi
  done < <(find "${APP_PATH}/Contents/MacOS" -type f -print0)

  sign_path "${APP_PATH}" --options runtime
  codesign --verify --deep --strict "${APP_PATH}"
elif [[ "${REQUIRE_NOTARIZATION}" == "1" ]]; then
  echo "[sign-and-notarize-boss-ui] BOSS_MACOS_DEVELOPER_IDENTITY is required when notarization is enforced" >&2
  exit 1
fi

if [[ -n "${NOTARY_PROFILE}" ]]; then
  tmp_dir="$(mktemp -d)"
  cleanup() {
    rm -rf "${tmp_dir}"
  }
  trap cleanup EXIT

  submit_zip="${tmp_dir}/Boss-notary.zip"
  ditto -c -k --sequesterRsrc --keepParent "${APP_PATH}" "${submit_zip}"
  xcrun notarytool submit "${submit_zip}" --keychain-profile "${NOTARY_PROFILE}" --wait
  xcrun stapler staple "${APP_PATH}"
  xcrun stapler validate "${APP_PATH}"
elif [[ "${REQUIRE_NOTARIZATION}" == "1" ]]; then
  echo "[sign-and-notarize-boss-ui] BOSS_MACOS_NOTARY_KEYCHAIN_PROFILE is required when notarization is enforced" >&2
  exit 1
fi

rm -f "${ZIP_PATH}"
mkdir -p "$(dirname "${ZIP_PATH}")"
ditto -c -k --sequesterRsrc --keepParent "${APP_PATH}" "${ZIP_PATH}"
