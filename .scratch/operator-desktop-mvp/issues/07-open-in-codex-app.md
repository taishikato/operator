# Open in Codex App

Status: ready-for-human
Type: AFK

## Parent

`.scratch/operator-desktop-mvp/PRD.md`

## What to build

Add the "Open in Codex App" path for successful tasks. Review, Done, and Archived tasks with a successful Run should expose a way to open the associated Codex thread. The primary path should use the saved Codex thread deep link when available. If direct thread opening is unavailable or unverified, fall back to opening Codex with the run worktree path.

This slice should not inspect Codex state or require Codex completion. It is only a navigation bridge from Operator to Codex App.

Scope this to the native SwiftUI desktop app. Ignore `webapp/`; it is reference material only.

Operator remains a trigger/navigation surface only. This issue must not add Codex completion tracking, transcript reads, diff inspection, progress polling, PR creation, or merge detection.

## Acceptance criteria

- [x] Review tasks with a successful Run show "Open in Codex App".
- [x] Done tasks with a successful Run show "Open in Codex App".
- [x] Archived tasks with a successful Run show "Open in Codex App".
- [x] Ready tasks do not show "Open in Codex App".
- [x] The preferred open target uses the saved Codex thread URL/reference.
- [x] A fallback open target uses the run worktree path.
- [x] Opening is implemented as an OS-level app/deep-link action.
- [x] If opening fails, the app shows a short user-facing error.
- [x] The feature does not read thread contents, completion status, transcript, diff, or Codex progress.
- [x] Deep link construction is covered by tests separately from OS opening behavior.

## Implementation notes

- `06-codex-app-server-trigger.md` is complete and merged into `feature/desktop` via PR #23.
- Use the successful Run data created by the Codex trigger flow; do not introduce a separate Codex state model.
- Use TDD for deep link target selection and failure handling. Inject the OS opener so tests do not launch Codex.
- Prefer the saved `codexThreadURL` when present; fall back to an open target derived from the run worktree path.
- The main action label is `Open in Codex App`.
