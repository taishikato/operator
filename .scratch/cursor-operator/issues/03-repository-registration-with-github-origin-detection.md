Status: ready-for-agent

# Repository registration with GitHub origin detection

## Parent

.scratch/cursor-operator/PRD.md

## What to build

Implement repository registration for local Git checkouts that have a GitHub origin. A user should be able to choose a folder, have Cursor Operator validate it as a Git repository, detect its GitHub remote and default branch, review or edit the detected values, and save the repository for later task creation.

The slice should make the remote-default-branch contract visible: Cursor Cloud Agent will start from the remote default branch, and local dirty or unpushed work is not included. Cursor Operator should not fetch, pull, push, merge, or rebase during this flow.

## Acceptance criteria

- [ ] Repository registration uses a native folder picker from the desktop app.
- [ ] Selected folders are validated as Git repositories before saving.
- [ ] A GitHub origin URL is required and normalized into the repository URL shape expected by Cursor Cloud Agent.
- [ ] Missing origin, non-Git folders, and unsupported remote URLs are rejected with clear user-facing errors.
- [ ] Default branch is detected and can be reviewed or edited before save.
- [ ] GitHub-only repository records without a local checkout are not allowed.
- [ ] The registration UI explains that Cursor Cloud Agent starts from the remote default branch and excludes local-only changes.
- [ ] Tests cover valid GitHub origin, missing origin, non-Git folder, unsupported remote URL, detected default branch, and edited default branch.

## Blocked by

- .scratch/cursor-operator/issues/01-app-shell-and-isolated-app-data.md
- .scratch/cursor-operator/issues/02-sqlite-store-and-task-lifecycle-policy.md
