#!/usr/bin/env bash
set -euo pipefail

APP_NAME="CursorOperator"
DISPLAY_NAME="Cursor Operator"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
RELEASE_DIR="${CURSOR_OPERATOR_RELEASE_DIR:-$DIST_DIR/release}"
STAGING_DIR="$DIST_DIR/dmg-staging"

usage() {
  cat <<USAGE
usage: $0 [dmg]

Builds a release app bundle and packages it as a DMG.

Environment:
  CURSOR_OPERATOR_VERSION              App/release version, e.g. 0.1.0
  CURSOR_OPERATOR_BUILD_NUMBER         CFBundleVersion build number
  CURSOR_OPERATOR_RELEASE_DIR          Output directory (default: dist/release)
  CURSOR_OPERATOR_CODESIGN_IDENTITY    Developer ID Application identity
  CURSOR_OPERATOR_NOTARIZE=1           Submit and staple the DMG
  CURSOR_OPERATOR_NOTARY_PROFILE       notarytool keychain profile
  APPLE_ID                             Apple ID for notarytool fallback auth
  APPLE_TEAM_ID                        Apple Team ID for notarytool fallback auth
  APPLE_APP_SPECIFIC_PASSWORD          App-specific password for fallback auth
USAGE
}

default_version() {
  git -C "$ROOT_DIR" describe --tags --match 'v[0-9]*' --abbrev=0 2>/dev/null \
    | sed 's/^v//' || printf '0.1.0\n'
}

default_build_number() {
  git -C "$ROOT_DIR" rev-list --count HEAD 2>/dev/null || printf '1\n'
}

require_version() {
  local version="$1"
  if [[ ! "$version" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]]; then
    echo "CURSOR_OPERATOR_VERSION must look like 0.1.0 for CFBundleShortVersionString." >&2
    exit 2
  fi
}

sign_app_if_requested() {
  local identity="${CURSOR_OPERATOR_CODESIGN_IDENTITY:-}"

  if [[ -z "$identity" ]]; then
    echo "Skipping Developer ID signing; set CURSOR_OPERATOR_CODESIGN_IDENTITY to sign for distribution."
    return
  fi

  sign_nested_mach_o_files "$identity"

  /usr/bin/codesign \
    --force \
    --options runtime \
    --timestamp \
    --sign "$identity" \
    "$APP_BUNDLE"
  /usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
}

sign_nested_mach_o_files() {
  local identity="$1"

  while IFS= read -r -d '' candidate; do
    if /usr/bin/file "$candidate" | /usr/bin/grep -q "Mach-O"; then
      /usr/bin/codesign \
        --force \
        --options runtime \
        --timestamp \
        --sign "$identity" \
        "$candidate"
    fi
  done < <(/usr/bin/find "$APP_CONTENTS" -type f -perm -111 -print0)
}

create_dmg() {
  local dmg_path="$1"

  rm -rf "$STAGING_DIR"
  mkdir -p "$STAGING_DIR" "$RELEASE_DIR"
  cp -R "$APP_BUNDLE" "$STAGING_DIR/"
  ln -s /Applications "$STAGING_DIR/Applications"

  rm -f "$dmg_path"
  /usr/bin/hdiutil create \
    -volname "$DISPLAY_NAME" \
    -srcfolder "$STAGING_DIR" \
    -format UDZO \
    -ov \
    "$dmg_path"
}

notarize_dmg_if_requested() {
  local dmg_path="$1"
  local auth_args=()
  local notary_result="$RELEASE_DIR/notarytool-$APP_NAME-$VERSION.json"
  local submission_id
  local status

  if [[ "${CURSOR_OPERATOR_NOTARIZE:-0}" != "1" ]]; then
    echo "Skipping notarization; set CURSOR_OPERATOR_NOTARIZE=1 after configuring notarytool credentials."
    return
  fi

  if [[ -z "${CURSOR_OPERATOR_CODESIGN_IDENTITY:-}" ]]; then
    echo "Notarization requires a Developer ID signed app. Set CURSOR_OPERATOR_CODESIGN_IDENTITY." >&2
    exit 2
  fi

  if [[ -n "${CURSOR_OPERATOR_NOTARY_PROFILE:-}" ]]; then
    auth_args=(--keychain-profile "$CURSOR_OPERATOR_NOTARY_PROFILE")
  else
    : "${APPLE_ID:?Set APPLE_ID or CURSOR_OPERATOR_NOTARY_PROFILE for notarization.}"
    : "${APPLE_TEAM_ID:?Set APPLE_TEAM_ID or CURSOR_OPERATOR_NOTARY_PROFILE for notarization.}"
    : "${APPLE_APP_SPECIFIC_PASSWORD:?Set APPLE_APP_SPECIFIC_PASSWORD or CURSOR_OPERATOR_NOTARY_PROFILE for notarization.}"
    auth_args=(
      --apple-id "$APPLE_ID"
      --team-id "$APPLE_TEAM_ID"
      --password "$APPLE_APP_SPECIFIC_PASSWORD"
    )
  fi

  /usr/bin/xcrun notarytool submit "$dmg_path" \
    "${auth_args[@]}" \
    --wait \
    --output-format json \
    | tee "$notary_result"

  status="$(/usr/bin/plutil -extract status raw -o - "$notary_result" 2>/dev/null || true)"
  submission_id="$(/usr/bin/plutil -extract id raw -o - "$notary_result" 2>/dev/null || true)"

  if [[ "$status" != "Accepted" ]]; then
    echo "Notarization failed with status: ${status:-unknown}." >&2
    if [[ -n "$submission_id" ]]; then
      /usr/bin/xcrun notarytool log "$submission_id" "${auth_args[@]}" || true
    fi
    exit 1
  fi

  /usr/bin/xcrun stapler staple "$dmg_path"
  /usr/bin/xcrun stapler validate "$dmg_path"
}

case "${1:-dmg}" in
  dmg)
    ;;
  -h|--help|help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

VERSION="${CURSOR_OPERATOR_VERSION:-$(default_version)}"
BUILD_NUMBER="${CURSOR_OPERATOR_BUILD_NUMBER:-$(default_build_number)}"
DMG_PATH="$RELEASE_DIR/$APP_NAME-$VERSION.dmg"

require_version "$VERSION"

CURSOR_OPERATOR_VERSION="$VERSION" \
CURSOR_OPERATOR_BUILD_NUMBER="$BUILD_NUMBER" \
CURSOR_OPERATOR_SWIFT_CONFIGURATION=release \
  "$ROOT_DIR/script/build_and_run.sh" --bundle

sign_app_if_requested
create_dmg "$DMG_PATH"
notarize_dmg_if_requested "$DMG_PATH"

/usr/bin/shasum -a 256 "$DMG_PATH" | tee "$DMG_PATH.sha256"
echo "Created $DMG_PATH"
