#!/usr/bin/env bash
#
# build-app.sh — compile the SwiftPM menu-bar app in release mode and assemble a
# runnable Claudemon.app bundle (LSUIElement menu-bar agent, no Dock icon).
#
# NOTE: This SwiftPM path builds the menu-bar app + floating panel ONLY; it does
# NOT include the WidgetKit extension or the App Group entitlements. For the
# full product (app + embedded widget, signed with App-Group entitlements), use
# scripts/build-xcode.sh instead. This script remains handy for a quick,
# dependency-light local run / QA smoke test of the core app.
#
# Usage:  ./scripts/build-app.sh
#
set -euo pipefail

# --- Config -----------------------------------------------------------------
APP_NAME="Claudemon"
BUNDLE_ID="com.claudemon.app"
MIN_MACOS="14.0"
APP_CATEGORY="public.app-category.developer-tools"

# Resolve project root (this script lives in <root>/scripts).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT_DIR}"

# SwiftPM build dir. Kept OUTSIDE the repo by default: llbuild's build.db
# (SQLite) throws "disk I/O error" when the scratch path contains spaces
# (this repo lives under ".../MacOS Projects/..."). Build into a space-free
# path via --scratch-path; override with CLAUDEMON_SCRATCH if needed.
SCRATCH="${CLAUDEMON_SCRATCH:-/tmp/claudemon-spm-build}"
BUILD_DIR="${SCRATCH}/release"
APP_BUNDLE="${ROOT_DIR}/${APP_NAME}.app"
CONTENTS="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS}/MacOS"
RESOURCES_DIR="${CONTENTS}/Resources"

# --- Build ------------------------------------------------------------------
echo "==> Building ${APP_NAME} (release)…"
swift build -c release --scratch-path "${SCRATCH}"

BINARY_PATH="${BUILD_DIR}/${APP_NAME}"
if [[ ! -f "${BINARY_PATH}" ]]; then
  echo "ERROR: built binary not found at ${BINARY_PATH}" >&2
  exit 1
fi

# --- Assemble bundle --------------------------------------------------------
echo "==> Assembling ${APP_NAME}.app…"
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"
cp "${BINARY_PATH}" "${MACOS_DIR}/${APP_NAME}"

cat > "${CONTENTS}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>${MIN_MACOS}</string>
    <key>LSApplicationCategoryType</key>
    <string>${APP_CATEGORY}</string>
    <!-- Pure menu-bar agent: no Dock icon. -->
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Claudemon</string>
</dict>
</plist>
PLIST

# Marker so launchservices treats the directory as an app bundle.
echo "APPL????" > "${CONTENTS}/PkgInfo"

# --- Ad-hoc signing (local run) ---------------------------------------------
# Ad-hoc signature lets the app run locally without a Developer ID.
# (--deep is deprecated and unnecessary for a single-binary bundle.)
echo "==> Ad-hoc signing…"
codesign --force --sign - "${APP_BUNDLE}"

# TODO (requires paid Apple Developer account):
#   1. Replace ad-hoc signing with a Developer ID Application identity:
#        codesign --force --options runtime --timestamp \
#          --sign "Developer ID Application: <NAME> (<TEAMID>)" "${APP_BUNDLE}"
#   2. Notarize:
#        ditto -c -k --keepParent "${APP_BUNDLE}" "${APP_NAME}.zip"
#        xcrun notarytool submit "${APP_NAME}.zip" --keychain-profile "<PROFILE>" --wait
#        xcrun stapler staple "${APP_BUNDLE}"

echo ""
echo "==> Done."
echo "    App bundle: ${APP_BUNDLE}"
echo "    Run with:   open \"${APP_BUNDLE}\""
