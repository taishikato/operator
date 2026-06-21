#!/bin/bash
# Builds the Cursor Operator CLI in release mode and symlinks it into
# ~/.local/bin as `cursor-operator`.
set -euo pipefail

cd "$(dirname "$0")/.."

swift build -c release --product cursor-operator-cli
BIN_PATH="$(swift build -c release --show-bin-path)/cursor-operator-cli"

INSTALL_DIR="${CURSOR_OPERATOR_CLI_INSTALL_DIR:-$HOME/.local/bin}"
mkdir -p "$INSTALL_DIR"
ln -sf "$BIN_PATH" "$INSTALL_DIR/cursor-operator"

echo "Installed: $INSTALL_DIR/cursor-operator -> $BIN_PATH"
case ":$PATH:" in
  *":$INSTALL_DIR:"*) ;;
  *) echo "Note: $INSTALL_DIR is not on your PATH. Add it, e.g.:"
     echo "  echo 'export PATH=\"$INSTALL_DIR:\$PATH\"' >> ~/.zshrc" ;;
esac
