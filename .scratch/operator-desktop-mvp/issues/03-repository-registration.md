# Repository Registration

Status: ready-for-agent
Type: AFK

## Parent

`.scratch/operator-desktop-mvp/PRD.md`

## What to build

Let the user register local Git repositories for Operator tasks. Repository registration should use a native folder picker, validate that the selected directory is a Git repository, infer the local default branch, and persist repository records. The user should be able to edit a repository's default branch later from settings.

This slice should make repository records real enough for task creation and worktree preparation to depend on them later.

## Acceptance criteria

- [ ] The user can add a repository using a native folder picker.
- [ ] The selected path is validated as a Git repository.
- [ ] Invalid folders produce a clear user-facing error.
- [ ] The repository name is inferred from the folder name.
- [ ] The local default branch is inferred when possible.
- [ ] The repository record persists across app restarts.
- [ ] Repository settings allow editing the stored default branch.
- [ ] Duplicate repository paths are handled predictably.
- [ ] Git validation and default-branch inference are covered by tests using temporary repositories.
- [ ] Registration does not fetch, pull, merge, or rebase.

## Blocked by

- `02-sqlite-store-and-task-lifecycle.md`
