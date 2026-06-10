# Plan 001: Recover Running tasks after an app restart

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**:
> `git diff --stat a8c3955..HEAD -- codex_operator/Sources/OperatorDesktop codex_operator/Tests`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: LOW
- **Depends on**: none
- **Category**: direction
- **Planned at**: commit `a8c3955`, 2026-06-10

## Why this matters

Operator moves a task from Running to Done when the Codex turn completes, but
the completion signal is only an in-memory `await` on the live stdio
connection to `codex app-server`. If Operator quits, crashes, or the
app-server process dies while a task is Running, `completeStartedRun` never
fires and the task is stuck in Running forever — there is no reconciliation
on relaunch and no manual way to move a Running task to Done (only Archive).
For a dogfooded daily tool this is the first robustness gap users will hit.
This plan adds a manual "Mark as Done" affordance for Running tasks (small,
certain win) and produces a written spike report on whether automatic
reconciliation via app-server is feasible.

## Current state

- `codex_operator/Sources/OperatorDesktop/Repositories/CodexTriggerService.swift`
  — send orchestration. The completion watch is in-memory only (lines 191–196):

  ```swift
  let store = store
  let turnCompletion = startedThread.turnCompletion
  Task {
      await turnCompletion.waitUntilCompleted()
      _ = try? store.completeStartedRun(id: run.id)
  }
  ```

- `codex_operator/Sources/OperatorDesktop/Models/TaskLifecycle.swift` — the
  transition Running→Done already exists as policy (lines ~71–77):

  ```swift
  public static func moveToDone(_ task: OperatorTask, now: Date = Date()) throws -> OperatorTask {
      guard task.status == .review else {
          throw TaskLifecycleError.transitionNotAllowed
      }
      return task.with(status: .done, now: now)
  }
  ```

  Note: the internal status for the "Running" column is `.review` (the column
  was renamed in the UI but not in code).

- `codex_operator/Sources/OperatorDesktop/Persistence/OperatorStore.swift` —
  `markTaskDone(id:now:)` exists at line ~252 and already enforces the policy.
  `completeStartedRun(id:now:)` at line ~337 is what the in-memory watcher
  calls; read it before step 2 to understand the run-row side of completion.

- `codex_operator/Sources/OperatorDesktop/Models/TaskBoardModel.swift` — the
  UI-facing model. The archive action is the exemplar pattern to copy
  (lines 379–388):

  ```swift
  public func archiveTask(taskID: UUID) throws {
      _ = try store.archiveTask(id: taskID)
      ...
  }

  public func archiveTaskReportingErrors(taskID: UUID) {
      do {
          try archiveTask(taskID: taskID)
      ...
  }
  ```

- `codex_operator/Sources/OperatorDesktop/Views/BoardView.swift` — card and
  inspector actions call the model, e.g.
  `model.archiveTaskReportingErrors(taskID: card.id)` at lines 428, 482, 670.
  Match the existing custom button/menu styles in this file (the repo
  deliberately replaced default glass controls — see commit `1006cfd`).

- `codex_operator/Sources/OperatorDesktop/Repositories/CodexAppServerStdioClient.swift`
  — JSON-RPC stdio client. Known methods used today: `initialize`,
  `thread/start`, `turn/start`, `thread/metadata/update`, `thread/name/set`;
  completion is detected from `turn/completed` / `turn/aborted` notifications
  (line ~311). Whether app-server exposes a *query* for past turn status is
  unknown — that is the spike question.

- `docs/codex-app-worktree-discovery.md` — exemplar for the spike report
  format (observed behavior, evidence, inference, design rules). Match it.

- Conventions: tests verify external behavior and state transitions, not
  SwiftUI internals (see "Testing Decisions" in
  `docs/operator-descktop-mvp.md`). Test exemplar:
  `codex_operator/Tests/OperatorDesktopTests/TaskBoardModelTests.swift`.

## Commands you will need

Run from `codex_operator/`:

| Purpose | Command      | Expected on success                  |
|---------|--------------|--------------------------------------|
| Tests   | `swift test` | exit 0; "126 tests" + new ones pass |
| Build   | `swift build`| exit 0                               |

(Verified at planning time: `swift test` passes with 126 tests.)

## Scope

**In scope** (the only files you should modify/create):
- `codex_operator/Sources/OperatorDesktop/Models/TaskBoardModel.swift`
- `codex_operator/Sources/OperatorDesktop/Views/BoardView.swift`
- `codex_operator/Tests/OperatorDesktopTests/TaskBoardModelTests.swift`
- `docs/running-task-recovery-spike.md` (create — spike report)

**Out of scope** (do NOT touch, even though they look related):
- `CodexTriggerService.swift`, `CodexAppServerStdioClient.swift` — do not
  implement automatic reconciliation in this plan; the spike only reports.
- `TaskLifecycle.swift`, `OperatorStore.swift` — the needed transitions
  already exist; do not add new states.
- Archive flow and Done-column behavior.

## Git workflow

- Branch: `advisor/001-running-task-recovery`
- Commit style: conventional, e.g. `feat: allow marking running tasks done`
  (matches `git log`, e.g. `feat: show repository onboarding modal`).
- Do NOT push or open a PR unless the operator instructed it.
- Repo rule (CLAUDE.md): PRs are merged without squashing — do not squash.

## Steps

### Step 1: Add `markTaskDoneReportingErrors` to TaskBoardModel

In `TaskBoardModel.swift`, add `markTaskDone(taskID:)` and
`markTaskDoneReportingErrors(taskID:)` copying the archive pair at lines
379–388 exactly, but calling `store.markTaskDone(id:)` instead of
`store.archiveTask(id:)`.

**Verify**: `swift build` from `codex_operator/` → exit 0.

### Step 2: Write the model tests first, then make them pass

In `TaskBoardModelTests.swift`, following the structure of the existing
archive tests, add:
- marking a Running (`.review`) task done moves it to the Done column;
- marking a Ready task done is rejected and surfaces an error through the
  same error-reporting path the archive tests assert on;
- marking a Done task done is rejected.

**Verify**: `swift test` from `codex_operator/` → exit 0, new tests listed
as passing.

### Step 3: Surface "Mark as Done" in the UI for Running tasks only

In `BoardView.swift`, add a "Mark as Done" action on Running-column cards and
in the inspector when the inspected task is Running, wired to
`model.markTaskDoneReportingErrors(taskID:)`. Place and style it like the
existing archive action (lines 428, 482, 670) including its hover/confirm
affordance if one exists for archive. Do not show it for Ready, Done, or
Archived tasks.

**Verify**: `swift test` → exit 0; `swift build` → exit 0. Then launch with
`script/build_and_run.sh` and manually confirm a Running card offers
"Mark as Done" and a Ready card does not. (If you cannot run the GUI in your
environment, state that in your report instead of claiming manual
verification.)

### Step 4: Spike report on automatic reconciliation

Without changing source code, investigate whether `codex app-server` can
answer "is this thread's last turn finished?" after a restart. Inputs:
run `codex app-server --listen stdio://` manually and probe `thread/list` /
any thread-status methods; consult the locally generated app-server schema if
present under `~/.codex`; reread `docs/codex-app-worktree-discovery.md` for
observed `thread/list` behavior (exact-path cwd filtering).

Write `docs/running-task-recovery-spike.md` in the same format as
`docs/codex-app-worktree-discovery.md`, covering: what status queries exist,
evidence (request/response shapes observed), whether on-launch reconciliation
is feasible, and a recommended follow-up design (or a recommendation against
it). Do NOT implement reconciliation.

**Verify**: file exists; `swift test` still exits 0; `git status` shows no
source files modified by this step.

## Test plan

- New tests in `TaskBoardModelTests.swift` (step 2): Running→Done allowed,
  Ready→Done rejected, Done→Done rejected — modeled after the existing
  archive tests in the same file.
- Verification: `swift test` → all pass, including ≥3 new tests.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `swift test` (from `codex_operator/`) exits 0 with ≥129 tests passing
- [ ] `grep -n "markTaskDoneReportingErrors" codex_operator/Sources/OperatorDesktop/Views/BoardView.swift` returns ≥1 match
- [ ] `docs/running-task-recovery-spike.md` exists and contains a section titled "Evidence"
- [ ] No files outside the in-scope list are modified (`git status`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- The archive pattern excerpts in "Current state" don't match the live code.
- `store.markTaskDone` does not exist or has a different signature than
  `markTaskDone(id:now:)`.
- The spike reveals that marking a task Done manually corrupts run records
  (e.g. `completeStartedRun` later fires for the same run and conflicts) —
  report the interaction instead of patching it.
- You find yourself wanting to edit `CodexTriggerService.swift` or the stdio
  client — that is the next plan's job, not this one's.

## Maintenance notes

- If automatic reconciliation is built later (per the spike), the manual
  "Mark as Done" action should remain as an override.
- Reviewer should scrutinize: the action must be status-gated to `.review`
  in the UI, and the model method must surface lifecycle errors the same way
  archive does.
- Deferred: persisting in-flight run state for crash-safe completion
  detection; that depends on the spike's findings.
