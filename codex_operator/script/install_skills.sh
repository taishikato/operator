#!/bin/bash
# Symlinks the operator agent skill into the personal skill directories of
# Claude Code (~/.claude/skills) and Codex (~/.codex/skills) so agents can
# file Operator tasks from any repo. Both ecosystems consume the same
# Agent Skills SKILL.md format.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SKILL_SOURCE="$REPO_ROOT/skills/operator"

if [[ ! -f "$SKILL_SOURCE/SKILL.md" ]]; then
  echo "error: $SKILL_SOURCE/SKILL.md not found" >&2
  exit 1
fi

for SKILLS_DIR in "$HOME/.claude/skills" "$HOME/.codex/skills"; do
  mkdir -p "$SKILLS_DIR"
  ln -sfn "$SKILL_SOURCE" "$SKILLS_DIR/operator"
  echo "Installed: $SKILLS_DIR/operator -> $SKILL_SOURCE"
done
