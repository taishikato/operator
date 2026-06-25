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
APP_FRAMEWORKS="$APP_CONTENTS/Frameworks"
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
SPARKLE_FRAMEWORK_NAME="Sparkle.framework"

cd "$ROOT_DIR"

truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|on|ON)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

xml_escape() {
  printf '%s' "$1" \
    | /usr/bin/sed \
      -e 's/&/\&amp;/g' \
      -e 's/</\&lt;/g' \
      -e 's/>/\&gt;/g' \
      -e 's/"/\&quot;/g' \
      -e "s/'/\&apos;/g"
}

plist_bool() {
  if truthy "$1"; then
    printf '<true/>'
  else
    printf '<false/>'
  fi
}

sparkle_info_plist_keys() {
  local feed_url="${CURSOR_OPERATOR_APPCAST_URL:-}"
  local public_key="${CURSOR_OPERATOR_SPARKLE_PUBLIC_ED_KEY:-}"

  if [[ -z "$feed_url" && -z "$public_key" ]]; then
    return
  fi

  if [[ -z "$feed_url" || -z "$public_key" ]]; then
    echo "CURSOR_OPERATOR_APPCAST_URL and CURSOR_OPERATOR_SPARKLE_PUBLIC_ED_KEY must be set together." >&2
    exit 2
  fi

  cat <<PLIST
  <key>SUFeedURL</key>
  <string>$(xml_escape "$feed_url")</string>
  <key>SUPublicEDKey</key>
  <string>$(xml_escape "$public_key")</string>
  <key>SUEnableAutomaticChecks</key>
  $(plist_bool "${CURSOR_OPERATOR_ENABLE_AUTOMATIC_UPDATE_CHECKS:-1}")
  <key>SUAutomaticallyUpdate</key>
  $(plist_bool "${CURSOR_OPERATOR_AUTOMATICALLY_UPDATE:-0}")
  <key>SUVerifyUpdateBeforeExtraction</key>
  $(plist_bool "${CURSOR_OPERATOR_VERIFY_UPDATE_BEFORE_EXTRACTION:-1}")
  <key>SURequireSignedFeed</key>
  $(plist_bool "${CURSOR_OPERATOR_REQUIRE_SIGNED_FEED:-0}")
PLIST
}

copy_sparkle_framework() {
  local framework_src
  framework_src="$(/usr/bin/find "$ROOT_DIR/.build" -name "$SPARKLE_FRAMEWORK_NAME" -type d -print -quit)"

  if [[ -z "$framework_src" ]]; then
    echo "missing $SPARKLE_FRAMEWORK_NAME in SwiftPM build artifacts." >&2
    exit 1
  fi

  /usr/bin/ditto "$framework_src" "$APP_FRAMEWORKS/$SPARKLE_FRAMEWORK_NAME"
}

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

swift build -c "$SWIFT_CONFIGURATION"
BUILD_BIN_DIR="$(swift build -c "$SWIFT_CONFIGURATION" --show-bin-path)"
BUILD_BINARY="$BUILD_BIN_DIR/$APP_NAME"
BUILD_CLI="$BUILD_BIN_DIR/cursor-operator-cli"
SPARKLE_INFO_PLIST_KEYS="$(sparkle_info_plist_keys)"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_FRAMEWORKS" "$APP_HELPERS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
cp "$BUILD_CLI" "$APP_CLI"
chmod +x "$APP_CLI"
copy_sparkle_framework

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
$SPARKLE_INFO_PLIST_KEYS
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
