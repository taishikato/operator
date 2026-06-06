# Codex App-Server Trigger

Status: ready-for-human
Type: AFK

## Parent

`.scratch/operator-desktop-mvp/PRD.md`

## What to build

Implement "Send to Codex" for Ready tasks. The app should lazily spawn `codex app-server` over stdio, initialize the app-server connection, start a new Codex thread with the prepared worktree as the working directory, and start the first turn using the Task prompt exactly as written.

Operator should consider the send successful once the Codex thread and initial turn are accepted by app-server. On success, store the Codex thread reference and move the Task to Review. On failure, leave the Task in Ready and store a short error message.

Scope this to the native SwiftUI desktop app. Ignore `webapp/`; it is reference material only.

Operator is only the trigger surface for Codex. Do not track Codex completion, read transcripts, inspect diffs, judge success, or persist Codex logs. After app-server accepts the thread and initial turn, Operator's trigger job is done.

## Acceptance criteria

- [x] Ready task cards expose a "Send to Codex" action.
- [x] Ready task inspector exposes a primary "Send to Codex" action.
- [x] Sending shows "Sending..." while worktree preparation and app-server triggering are in progress.
- [x] `codex app-server` is spawned lazily only when sending requires it.
- [x] app-server communication uses stdio.
- [x] The Codex App does not need to be running.
- [x] The app-server thread is started with the prepared worktree as cwd.
- [x] The model parameter is fixed to `gpt-5.5`.
- [x] The selected reasoning effort is passed as an app-server parameter.
- [x] The Task prompt is sent exactly as written.
- [x] Operator does not append hidden instructions or metadata to the prompt.
- [x] Trigger success stores the Codex thread reference.
- [x] Trigger success moves the Task to Review.
- [x] Trigger failure leaves the Task in Ready.
- [x] Trigger failure stores a short error message.
- [x] Failed trigger retry creates a new Run record and a new worktree.
- [x] Successful Tasks cannot be sent again.
- [x] App-server notifications are drained but not persisted.
- [x] Tests use a fake app-server client or transport and do not require real Codex.

## Implementation notes

- `05-detached-worktree-preparation.md` is complete and merged into `feature/desktop` via PR #22.
- Use the existing detached worktree preparation flow from `WorktreePreparer`.
- Use TDD for the implementation. Add tests with a fake app-server client or stdio transport before adding production code.
- Do not add scheduling, automatic cleanup, PR creation, merge detection, completion polling, transcript storage, or diff inspection in this issue.
