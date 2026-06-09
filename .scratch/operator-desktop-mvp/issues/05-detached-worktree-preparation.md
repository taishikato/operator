# Detached Worktree Preparation

Status: ready-for-human
Type: AFK

## Parent

`.scratch/operator-desktop-mvp/PRD.md`

## What to build

Create the worktree preparation module used before sending a task to Codex. Each trigger attempt should create a fresh detached Git worktree outside the repository, under the Operator app data directory, using the repository's stored local default branch as the base. The module should return provenance metadata including worktree path, base branch, and actual base ref.

This slice should be testable without Codex. It is the local Git preparation layer for later send orchestration.

## Acceptance criteria

- [x] A trigger attempt can create a detached worktree for a repository.
- [x] The worktree is created outside the repository under the Operator app data directory.
- [x] The worktree is created from the stored local default branch.
- [x] The worktree is detached HEAD and does not create a branch.
- [x] The module captures the actual base ref used.
- [x] The module returns worktree path, base branch, and base ref.
- [x] Each trigger attempt gets a fresh worktree path.
- [x] Failed worktree preparation stores a short trigger-level error.
- [x] Worktrees are not automatically cleaned up.
- [x] The module does not fetch, pull, merge, rebase, install dependencies, or run setup commands.
- [x] Tests verify detached state, no branch creation, base ref capture, and failure behavior.

## Blocked by

- `03-repository-registration.md`
- `04-task-creation-and-inspector.md`

## Comments

- Implemented in `7540f34` with `WorktreePreparer` and `WorktreePreparerTests`.
- Verified with `swift test`.
