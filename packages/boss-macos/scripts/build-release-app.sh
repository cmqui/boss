#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${PACKAGE_DIR}"

APP_NAME="Boss"
DIST_DIR="${PACKAGE_DIR}/dist"
APP_DIR="${DIST_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
ICON_SOURCE="${PACKAGE_DIR}/Sources/BossMacOS/Resources/BossLogo.png"
ICONSET_DIR="${DIST_DIR}/${APP_NAME}.iconset"
ICNS_PATH="${RESOURCES_DIR}/${APP_NAME}.icns"

echo "[build-release-app] Building ${APP_NAME} in release mode"
swift build -c release --product "${APP_NAME}"

BIN_DIR="$(swift build -c release --show-bin-path)"
BIN_PATH="${BIN_DIR}/${APP_NAME}"

if [[ ! -x "${BIN_PATH}" ]]; then
  echo "[build-release-app] Expected executable at ${BIN_PATH} but it was not found" >&2
  exit 1
fi

rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cp "${BIN_PATH}" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"

if [[ -f "${ICON_SOURCE}" ]]; then
  rm -rf "${ICONSET_DIR}"
  mkdir -p "${ICONSET_DIR}"

  sips -z 16 16 "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_16x16.png" >/dev/null
  sips -z 32 32 "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_16x16@2x.png" >/dev/null
  sips -z 32 32 "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_32x32.png" >/dev/null
  sips -z 64 64 "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_32x32@2x.png" >/dev/null
  sips -z 128 128 "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_128x128.png" >/dev/null
  sips -z 256 256 "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_128x128@2x.png" >/dev/null
  sips -z 256 256 "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_256x256.png" >/dev/null
  sips -z 512 512 "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_256x256@2x.png" >/dev/null
  sips -z 512 512 "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_512x512.png" >/dev/null
  cp "${ICON_SOURCE}" "${ICONSET_DIR}/icon_512x512@2x.png"

  iconutil -c icns "${ICONSET_DIR}" -o "${ICNS_PATH}"
  rm -rf "${ICONSET_DIR}"
fi

cat > "${CONTENTS_DIR}/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>Boss</string>
    <key>CFBundleIconFile</key>
    <string>Boss</string>
    <key>CFBundleIdentifier</key>
    <string>dev.local.boss</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Boss</string>
    <key>CFBundleDisplayName</key>
    <string>Boss</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>Boss uses Bluetooth to discover and connect to your Bose headphones so it can read and change device settings.</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

codesign --force --deep --sign - --timestamp=none "${APP_DIR}"

echo "[build-release-app] App bundle created at ${APP_DIR}"
