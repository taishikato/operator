#!/bin/bash
# Symlinks the Cursor Operator agent skill into personal agent skill
# directories. This skill is intentionally separate from codex_operator's
# Operator skill because it targets Cursor Cloud Agent tasks and storage.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SKILL_SOURCE="$REPO_ROOT/cursor_operator/skills/cursor-operator"

if [[ ! -f "$SKILL_SOURCE/SKILL.md" ]]; then
  echo "error: $SKILL_SOURCE/SKILL.md not found" >&2
  exit 1
fi

for SKILLS_DIR in "$HOME/.codex/skills" "$HOME/.cursor/skills" "$HOME/.claude/skills"; do
  mkdir -p "$SKILLS_DIR"
  ln -sfn "$SKILL_SOURCE" "$SKILLS_DIR/cursor-operator"
  echo "Installed: $SKILLS_DIR/cursor-operator -> $SKILL_SOURCE"
done
