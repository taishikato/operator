# Codex Thread Visibility Discovery

This document captures how Operator Desktop hides an in-flight Codex thread
from the Codex App sidebar until the task reaches Done, and the codex
app-server behavior discovered while building it.

## Date

2026-06-11

## Why This Matters

Previously, an Operator-triggered thread appeared in the Codex App sidebar as
soon as the first model output started streaming. The desired behavior is that
the thread becomes visible in Codex App only when the turn has fully completed
and the Operator task moves to the Done column.

## Findings (codex-cli 0.137.0)

All findings come from the generated app-server JSON schema
(`codex app-server generate-json-schema`), the `openai/codex` source at tag
`rust-v0.137.0`, and live experiments against the real app-server.

### When a thread becomes visible

- `thread/start` alone creates **nothing on disk**: no rollout file under
  `~/.codex/sessions/` and no row in `~/.codex/state_5.sqlite`.
- Both are created lazily when the first `turn/start` begins. This is the
  moment the thread appears in the Codex App sidebar, which matches the
  observed "appears at the first thinking response" behavior.
- The sidebar is effectively `thread/list` with the default
  `archived: false` filter, backed by the state DB plus a scan-and-repair pass
  over the rollout JSONL files in `sessions/`.

### Archive semantics

- `thread/archive` exists in the app-server API and as a `codex archive`
  CLI subcommand. It renames the rollout file into
  `~/.codex/archived_sessions/` and sets `archived`/`archived_at` on the state
  DB row. Archived threads are excluded from the default `thread/list`.
- Critically, the app-server handler (`prepare_thread_for_archive`) **shuts
  down the thread if it is loaded in that same process**. Archiving through
  Operator's own app-server connection would kill the running turn.
- Archiving from a **separate process** (the `codex archive` CLI, or any other
  app-server instance) does not touch the thread loaded in Operator's
  app-server process. The rollout writer holds an open file descriptor, so it
  keeps appending to the renamed file in `archived_sessions/`.
- During the run, incremental state DB updates (`apply_rollout_items`) start
  from the existing row and **preserve `archived_at`**, so the thread stays
  hidden for the whole turn.
- `thread/resume` and `thread/fork` both reject archived threads
  ("session ... is archived"), so mid-run takeover from Codex App is not
  possible while hidden. `turn/start` requires an already-loaded thread, which
  Operator's own app-server still has.
- Flipping only the SQLite `archived` flag without moving the file does not
  work: the scan-and-repair pass treats any rollout found under `sessions/` as
  non-archived and reverts the flag. The real archive (file move + DB flag)
  must be used.
- `thread/unarchive` restores the file to `sessions/<YYYY>/<MM>/<DD>/` derived
  from the rollout filename timestamp — exactly the original path the open
  writer still points at — clears the archived flag, and bumps the modified
  time so the thread sorts to the top of the sidebar.

### Rejected alternatives

- Archive before `turn/start`: nothing exists to archive yet, and after an
  archive the thread is unloaded while `thread/resume` rejects archived
  threads.
- `ephemeral: true` threads: never persisted, and `thread/fork` cannot fork
  them because it reads history from disk.
- Pointing `CODEX_HOME` at a private directory and moving the rollout at the
  end: works in principle but requires duplicating `auth.json`, risking token
  refresh divergence with the user's real Codex login.

## Live Experiment

Verified against the real `codex app-server` (0.137.0) with one small turn:

1. `thread/start` → no file, no DB row.
2. `turn/start` sent; `codex archive <id>` from a separate process succeeded
   0.27s later (first attempt) — the rollout had just been created.
3. Mid-run and at `turn/completed`: rollout stayed in `archived_sessions/`,
   DB row stayed `archived=1`. The turn streamed and completed normally.
4. `thread/unarchive` on the same app-server connection restored the rollout
   to `sessions/2026/06/11/...`, cleared the flag, and the full transcript
   (including the agent reply) was intact.

## Implemented Design

- `CodexCLIThreadVisibilityController` runs `codex archive <thread-id>`
  (hide) and `codex unarchive <thread-id>` (reveal) as separate processes,
  using the same configured Codex binary as the app-server client.
- `CodexTriggerService.sendTaskToCodex`:
  - after `startThreadAndTurn` succeeds, starts a hide task that polls
    `codex archive` (150ms interval, 15s budget) until the lazily created
    rollout exists;
  - when the turn completes, cancels the hide task, awaits its result, and
    only if the thread was actually hidden runs reveal (3 attempts) **before**
    `completeStartedRun` moves the task to Done. This ordering means the
    thread appears in Codex App at the same moment the card lands in Done.
- Crash safety:
  - if the spawned app-server dies mid-run, the stdio client now completes
    pending turn watchers, so the reveal + Done transition still run;
  - `CodexTriggerService.recoverInterruptedRuns()` runs at app launch and,
    for runs still marked running from a previous session, reveals their
    threads and completes the runs (the app-server child cannot outlive the
    app, so those turns are dead).
- Hide and reveal are best-effort: if `codex archive` never succeeds the
  thread simply stays visible (previous behavior); if `codex unarchive` fails
  the task still reaches Done.

## Known Trade-offs

- There is a small window (typically well under a second) between rollout
  creation at turn start and the first successful archive in which Codex App
  could briefly list the thread.
- While a task is Running, the saved `codex://threads/<id>` deep link points
  at an archived thread; opening or continuing it from Codex App is expected
  to fail until the task reaches Done. This intentionally supersedes the MVP
  story that exposed "Open in Codex App" for Running tasks.
- During the run the thread is visible in Codex App's archived threads list.
- This is observed integration behavior, not a stable public contract. Verify
  the regression checklist below after Codex CLI upgrades.

## Regression Checks

1. Send a new Operator task and keep Codex App open on the source repo.
2. Confirm no new thread appears in the sidebar while the task is Running.
3. Wait for the task to move to Done; confirm the thread then appears under
   the expected repository with the full transcript.
4. Open the thread via "Open in Codex App" and continue it; confirm the turn
   runs in the worktree (see codex-app-worktree-discovery.md).
5. Quit Operator while a task is Running, relaunch, and confirm the task
   completes to Done and the thread becomes visible.

## Related Code

- `codex_operator/Sources/OperatorDesktop/Repositories/CodexThreadVisibilityController.swift`
- `codex_operator/Sources/OperatorDesktop/Repositories/CodexTriggerService.swift`
- `codex_operator/Sources/OperatorDesktop/Repositories/CodexAppServerStdioClient.swift`
- `codex_operator/Sources/OperatorApp/OperatorApp.swift`

## Related Docs

- `docs/codex-app-worktree-discovery.md` — worktree placement and sidebar
  grouping behavior.
