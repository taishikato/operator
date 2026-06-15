#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Operator"
BUNDLE_ID="com.focus.operator.desktop"
MIN_SYSTEM_VERSION="26.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
RELEASE_DIR="$DIST_DIR/release"
STAGING_DIR="$RELEASE_DIR/staging"
APP_BUNDLE="$STAGING_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_HELPERS="$APP_CONTENTS/Library/Helpers"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
APP_CLI="$APP_HELPERS/operator-cli"
APP_ICON="$APP_RESOURCES/AppIcon.icns"
INFO_PLIST="$APP_CONTENTS/Info.plist"
LOGO_PNG="$ROOT_DIR/Resources/Assets/operator-logo.png"
SKILL_SOURCE="$ROOT_DIR/../skills/operator"
APP_SKILLS_DIR="$APP_RESOURCES/skills"
DMG_PATH="$RELEASE_DIR/$APP_NAME.dmg"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 1
  fi
}

require_command swift
require_command hdiutil
require_command shasum

cd "$ROOT_DIR"

rm -rf "$RELEASE_DIR"
mkdir -p "$APP_MACOS" "$APP_HELPERS" "$APP_RESOURCES"

swift build -c release
BUILD_BINARY="$(swift build -c release --show-bin-path)/$APP_NAME"
BUILD_CLI="$(swift build -c release --show-bin-path)/operator-cli"

cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
cp "$BUILD_CLI" "$APP_CLI"
chmod +x "$APP_CLI"

if [[ -d "$SKILL_SOURCE" ]]; then
  mkdir -p "$APP_SKILLS_DIR"
  cp -R "$SKILL_SOURCE" "$APP_SKILLS_DIR/operator"
else
  echo "missing skill source: $SKILL_SOURCE" >&2
  exit 1
fi

if [[ -f "$LOGO_PNG" ]]; then
  require_command sips
  require_command iconutil

  ICONSET="$RELEASE_DIR/AppIcon.iconset"
  mkdir -p "$ICONSET"
  sips -z 16 16 "$LOGO_PNG" --out "$ICONSET/icon_16x16.png" >/dev/null
  sips -z 32 32 "$LOGO_PNG" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
  sips -z 32 32 "$LOGO_PNG" --out "$ICONSET/icon_32x32.png" >/dev/null
  sips -z 64 64 "$LOGO_PNG" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
  sips -z 128 128 "$LOGO_PNG" --out "$ICONSET/icon_128x128.png" >/dev/null
  sips -z 256 256 "$LOGO_PNG" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
  sips -z 256 256 "$LOGO_PNG" --out "$ICONSET/icon_256x256.png" >/dev/null
  sips -z 512 512 "$LOGO_PNG" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
  sips -z 512 512 "$LOGO_PNG" --out "$ICONSET/icon_512x512.png" >/dev/null
  sips -z 1024 1024 "$LOGO_PNG" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
  iconutil -c icns "$ICONSET" -o "$APP_ICON"
  rm -rf "$ICONSET"
fi

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  require_command codesign
  codesign \
    --force \
    --options runtime \
    --timestamp \
    --sign "$CODESIGN_IDENTITY" \
    "$APP_BUNDLE"
  codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
else
  echo "CODESIGN_IDENTITY is not set; creating an unsigned DMG." >&2
fi

ln -s /Applications "$STAGING_DIR/Applications"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

if [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]]; then
  require_command xcrun
  xcrun notarytool submit "$DMG_PATH" \
    --apple-id "$APPLE_ID" \
    --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_SPECIFIC_PASSWORD" \
    --wait
  xcrun stapler staple "$DMG_PATH"
else
  echo "Apple notarization environment is not set; skipping notarization." >&2
fi

shasum -a 256 "$DMG_PATH" >"$DMG_PATH.sha256"

echo "Created $DMG_PATH"
echo "Created $DMG_PATH.sha256"
