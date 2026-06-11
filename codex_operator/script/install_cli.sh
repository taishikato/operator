#!/bin/bash
# Builds the operator CLI in release mode and symlinks it into ~/.local/bin
# as `operator`. The product itself is named operator-cli because an
# executable literally named `operator` would collide with the Operator app
# product on macOS's case-insensitive filesystem.
set -euo pipefail

cd "$(dirname "$0")/.."

swift build -c release --product operator-cli
BIN_PATH="$(swift build -c release --show-bin-path)/operator-cli"

INSTALL_DIR="${OPERATOR_CLI_INSTALL_DIR:-$HOME/.local/bin}"
mkdir -p "$INSTALL_DIR"
ln -sf "$BIN_PATH" "$INSTALL_DIR/operator"

echo "Installed: $INSTALL_DIR/operator -> $BIN_PATH"
case ":$PATH:" in
  *":$INSTALL_DIR:"*) ;;
  *) echo "Note: $INSTALL_DIR is not on your PATH. Add it, e.g.:"
     echo "  echo 'export PATH=\"$INSTALL_DIR:\$PATH\"' >> ~/.zshrc" ;;
esac
