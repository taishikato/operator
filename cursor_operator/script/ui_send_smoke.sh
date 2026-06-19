#!/usr/bin/env bash
set -euo pipefail

APP_NAME="CursorOperator"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
SMOKE_ROOT="${TMPDIR:-/tmp}/cursor-operator-ui-send-smoke-$$"
APP_SUPPORT_DIR="$SMOKE_ROOT/app-support"
DATABASE_URL="$APP_SUPPORT_DIR/cursor-operator.sqlite"
PROMPT="${CURSOR_OPERATOR_SMOKE_PROMPT:-Please reply with exactly: cursor operator ui send smoke ok. Do not modify files or create a pull request.}"
REPOSITORY_URL=""
STARTING_REF=""

if [[ -z "${CURSOR_API_KEY:-}" ]]; then
  echo "CURSOR_API_KEY is required for the UI send smoke test." >&2
  exit 2
fi

preflight_accessibility() {
  if ! osascript -e 'tell application "System Events" to get name of UI elements of first process' >/dev/null 2>&1; then
    echo "Accessibility permission is required for UI send smoke." >&2
    echo "Grant assistive access to the terminal running this script, then rerun ./script/ui_send_smoke.sh." >&2
    exit 3
  fi
}

cleanup() {
  launchctl unsetenv CURSOR_API_KEY >/dev/null 2>&1 || true
  launchctl unsetenv CURSOR_OPERATOR_APP_SUPPORT_DIR >/dev/null 2>&1 || true
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  if [[ -n "$REPOSITORY_URL" && -n "$STARTING_REF" ]]; then
    swift run CursorOperatorSmokeSupport cleanup \
      --database "$DATABASE_URL" \
      --repository-url "$REPOSITORY_URL" \
      --starting-ref "$STARTING_REF" >/dev/null 2>&1 || true
  else
    rm -rf "$SMOKE_ROOT" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

cd "$ROOT_DIR"

preflight_accessibility

./script/build_and_run.sh --bundle

REMOTE_URL="${CURSOR_OPERATOR_SMOKE_REPOSITORY_URL:-$(git remote get-url origin)}"
case "$REMOTE_URL" in
  git@github.com:*)
    REPOSITORY_URL="https://github.com/${REMOTE_URL#git@github.com:}"
    REPOSITORY_URL="${REPOSITORY_URL%.git}"
    ;;
  https://github.com/*.git)
    REPOSITORY_URL="${REMOTE_URL%.git}"
    ;;
  *)
    REPOSITORY_URL="$REMOTE_URL"
    ;;
esac

if [[ -n "${CURSOR_OPERATOR_SMOKE_STARTING_REF:-}" ]]; then
  STARTING_REF="$CURSOR_OPERATOR_SMOKE_STARTING_REF"
else
  STARTING_REF="$(git ls-remote --symref origin HEAD | awk '/^ref:/ { sub("refs/heads/", "", $2); print $2; exit }')"
fi

mkdir -p "$APP_SUPPORT_DIR"

TASK_ID="$(swift run CursorOperatorSmokeSupport seed-ready \
  --database "$DATABASE_URL" \
  --repository-url "$REPOSITORY_URL" \
  --starting-ref "$STARTING_REF" \
  --local-path "$ROOT_DIR/.." \
  --prompt "$PROMPT")"

launchctl setenv CURSOR_API_KEY "$CURSOR_API_KEY"
launchctl setenv CURSOR_OPERATOR_APP_SUPPORT_DIR "$APP_SUPPORT_DIR"

/usr/bin/open -n -F "$APP_BUNDLE"

osascript <<'APPLESCRIPT'
on clickSend(elementRef)
  tell application "System Events"
    try
      if role of elementRef is "AXButton" and name of elementRef is "Send" then
        click elementRef
        return true
      end if
    end try

    repeat with childRef in UI elements of elementRef
      if my clickSend(childRef) then return true
    end repeat
  end tell

  return false
end clickSend

tell application "Cursor Operator" to activate
tell application "System Events"
  tell process "Cursor Operator"
    repeat 80 times
      if exists window 1 then exit repeat
      delay 0.25
    end repeat

    if not (exists window 1) then error "Cursor Operator window did not appear."

    repeat 120 times
      if my clickSend(window 1) then return
      delay 0.5
    end repeat

    error "Send button was not found. Ensure Accessibility permission is granted for the terminal running this script."
  end tell
end tell
APPLESCRIPT

swift run CursorOperatorSmokeSupport wait-done \
  --database "$DATABASE_URL" \
  --repository-url "$REPOSITORY_URL" \
  --starting-ref "$STARTING_REF" \
  --task-id "$TASK_ID" \
  --timeout "${CURSOR_OPERATOR_SMOKE_TIMEOUT:-600}"

echo "UI send smoke passed for task $TASK_ID"
