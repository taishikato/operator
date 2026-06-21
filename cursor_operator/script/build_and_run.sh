#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="CursorOperator"
BUNDLE_ID="com.focus.cursor-operator"
MIN_SYSTEM_VERSION="26.0"
APP_VERSION="${CURSOR_OPERATOR_VERSION:-0.1.0}"
BUILD_NUMBER="${CURSOR_OPERATOR_BUILD_NUMBER:-1}"
SWIFT_CONFIGURATION="${CURSOR_OPERATOR_SWIFT_CONFIGURATION:-debug}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_HELPERS="$APP_CONTENTS/Library/Helpers"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
APP_CLI="$APP_HELPERS/cursor-operator-cli"
INFO_PLIST="$APP_CONTENTS/Info.plist"
SDK_HELPER_SRC="$ROOT_DIR/Resources/CursorSDKHelper"
SDK_HELPER_DST="$APP_RESOURCES/CursorSDKHelper"
APP_ICON_SRC="$ROOT_DIR/Resources/AppIcon.icns"
APP_ICON_FILE="AppIcon.icns"
SKILL_SOURCE="$ROOT_DIR/skills/cursor-operator"
APP_SKILLS_DIR="$APP_RESOURCES/skills"

cd "$ROOT_DIR"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

swift build -c "$SWIFT_CONFIGURATION"
BUILD_BINARY="$(swift build -c "$SWIFT_CONFIGURATION" --show-bin-path)/$APP_NAME"
BUILD_CLI="$(swift build -c "$SWIFT_CONFIGURATION" --show-bin-path)/cursor-operator-cli"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_HELPERS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
cp "$BUILD_CLI" "$APP_CLI"
chmod +x "$APP_CLI"

if [ -d "$SDK_HELPER_SRC" ]; then
  (cd "$SDK_HELPER_SRC" && npm install --omit=dev)
  cp -R "$SDK_HELPER_SRC" "$SDK_HELPER_DST"
fi

if [ -d "$SKILL_SOURCE" ]; then
  mkdir -p "$APP_SKILLS_DIR"
  cp -R "$SKILL_SOURCE" "$APP_SKILLS_DIR/cursor-operator"
else
  echo "missing skill source: $SKILL_SOURCE" >&2
  exit 1
fi

if [ -f "$APP_ICON_SRC" ]; then
  cp "$APP_ICON_SRC" "$APP_RESOURCES/$APP_ICON_FILE"
fi

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>Cursor Operator</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

open_app() {
  /usr/bin/open -n -F "$APP_BUNDLE"
}

case "$MODE" in
  --bundle|bundle)
    ;;
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--bundle|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
