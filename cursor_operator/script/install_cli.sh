#!/bin/bash
# Builds the Operator CLI in release mode and symlinks it into
# ~/.local/bin as `operator`.
set -euo pipefail

cd "$(dirname "$0")/.."

swift build -c release --product operator-cli
BIN_DIR="$(swift build -c release --show-bin-path)"
BIN_PATH="$BIN_DIR/operator-cli"
HELPER_SRC="$PWD/Resources/CursorSDKHelper"
HELPER_DEST="$BIN_DIR/CursorSDKHelper"

INSTALL_DIR="${CURSOR_OPERATOR_CLI_INSTALL_DIR:-$HOME/.local/bin}"
HELPER_INSTALL_DEST="$INSTALL_DIR/CursorSDKHelper"
mkdir -p "$INSTALL_DIR"
rm -rf "$HELPER_DEST"
cp -R "$HELPER_SRC" "$HELPER_DEST"
rm -rf "$HELPER_INSTALL_DEST"
cp -R "$HELPER_SRC" "$HELPER_INSTALL_DEST"
ln -sf "$BIN_PATH" "$INSTALL_DIR/operator"

echo "Installed: $INSTALL_DIR/operator -> $BIN_PATH"
case ":$PATH:" in
  *":$INSTALL_DIR:"*) ;;
  *) echo "Note: $INSTALL_DIR is not on your PATH. Add it, e.g.:"
     echo "  echo 'export PATH=\"$INSTALL_DIR:\$PATH\"' >> ~/.zshrc" ;;
esac
