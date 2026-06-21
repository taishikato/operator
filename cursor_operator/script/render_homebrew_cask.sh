#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
usage: $0 VERSION DMG_URL SHA256

Renders a Homebrew Cask for a signed and notarized Cursor Operator DMG.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || "${1:-}" == "help" ]]; then
  usage
  exit 0
fi

VERSION="${1:-${CURSOR_OPERATOR_VERSION:-}}"
DMG_URL="${2:-${CURSOR_OPERATOR_DMG_URL:-}}"
SHA256="${3:-${CURSOR_OPERATOR_SHA256:-}}"

if [[ -z "$VERSION" || -z "$DMG_URL" || -z "$SHA256" ]]; then
  usage >&2
  exit 2
fi

cat <<CASK
cask "cursor-operator" do
  version "$VERSION"
  sha256 "$SHA256"

  url "$DMG_URL",
      verified: "github.com/taishikato/operator/"
  name "Cursor Operator"
  desc "Prepare Cursor Cloud Agent tasks"
  homepage "https://github.com/taishikato/operator"

  depends_on formula: "node"
  depends_on macos: ">= :tahoe"

  app "CursorOperator.app"

  caveats <<~EOS
    Cursor Operator requires Node.js 22.13 or newer at runtime.
    If Homebrew's node is not the Node executable you want the app to use,
    set CURSOR_NODE_PATH to an executable Node.js 22.13+ binary.
  EOS

  zap trash: [
    "~/Library/Application Support/Cursor Operator",
    "~/Library/Preferences/com.focus.cursor-operator.plist",
    "~/Library/Saved Application State/com.focus.cursor-operator.savedState",
  ]
end
CASK
