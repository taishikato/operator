# Operator Desktop MVP PRD

Status: ready-for-agent

Source document: `docs/operator-descktop-mvp.md`

## Summary

Operator Desktop MVP is a native SwiftUI macOS app for preparing local tasks and sending them to Codex. Operator is not an agent runtime, log viewer, scheduler, PR tool, or Codex result judge. Its job is to bind a task to a local Git repository, prepare a detached worktree, trigger a Codex thread through `codex app-server`, store the trigger reference, and move the task to Review.

The full PRD lives in `docs/operator-descktop-mvp.md`. The implementation issues in this directory are the ready-for-agent breakdown for that PRD.

## Core Constraints

- Native SwiftUI macOS app, minimum macOS 15 Sequoia.
- Existing `webapp/` is UI reference only.
- SQLite persistence through GRDB.
- Board columns: Ready, Review, Done.
- Archived tasks are hidden from the default board.
- 1 Task belongs to 1 repo.
- 1 Task can have at most 1 successful Run.
- Failed trigger attempts can be retried from Ready.
- Each trigger attempt creates a new detached worktree.
- Successful trigger moves the Task to Review.
- Review, Done, and Archived task content is immutable.
- No rerun after successful trigger.
- No schedule, cron, timezone, queue, or concurrency feature in MVP.
- No Codex completion tracking, result classification, diff inspection, transcript storage, raw event storage, commits, PRs, or automatic cleanup.

## Issues

1. `issues/01-native-app-shell-and-board.md`
2. `issues/02-sqlite-store-and-task-lifecycle.md`
3. `issues/03-repository-registration.md`
4. `issues/04-task-creation-and-inspector.md`
5. `issues/05-detached-worktree-preparation.md`
6. `issues/06-codex-app-server-trigger.md`
7. `issues/07-open-in-codex-app.md`
8. `issues/08-settings-and-codex-status.md`
9. `issues/09-runtime-guardrails.md`
