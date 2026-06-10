# Plan 003: Design spike — follow-up sends and rerun after the MVP's one-shot constraint

> **Executor instructions**: This is a design spike. You will produce a PRD
> document, not code. Follow the steps, honor the STOP conditions, and when
> done update the status row for this plan in `plans/README.md` — unless a
> reviewer dispatched you and told you they maintain the index.
>
> **Drift check (run first)**:
> `git diff --stat a8c3955..HEAD -- codex_operator/Sources/OperatorDesktop/Models docs/operator-descktop-mvp.md`
> If the lifecycle model changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: S (spike only; implementation is a future plan)
- **Risk**: LOW (no code changes)
- **Depends on**: none (001's spike report is useful input if it exists, but not required)
- **Category**: direction
- **Planned at**: commit `a8c3955`, 2026-06-10

## Why this matters

The MVP deliberately allows exactly one successful send per task: "A task can
only be sent to Codex once after a successful trigger"
(`codex_operator/README.md:122`), with Rerun, Running→Ready, and multiple
successful runs all listed as out of scope in
`docs/operator-descktop-mvp.md`. That was right for the MVP, but it is the
first product wall in daily dogfooding: when Codex's first turn lands close
but not quite, the user's only options are to continue manually in Codex App
or create a brand-new task by hand, losing the board's relationship between
the task and the follow-up. This spike decides what the post-MVP send model
should be — before anyone starts loosening immutability rules ad hoc.

## Current state

- Lifecycle policy, `codex_operator/Sources/OperatorDesktop/Models/TaskLifecycle.swift`:
  statuses are `ready / review / done / archived` (`review` is the "Running"
  column). One successful run max is enforced
  (`TaskLifecycleError.taskAlreadyHasSuccessfulRun`); only `ready` tasks are
  editable or sendable; `moveToDone` requires `review`.
- Run relationship (from `docs/operator-descktop-mvp.md`, "Decision-rich run
  relationship"): a task has N failed runs and at most one successful run;
  a successful run has exactly one detached worktree and one Codex thread.
- Each trigger attempt creates a fresh detached worktree under
  `~/.codex/worktrees/<short-attempt-id>/<repo-name>`
  (`docs/codex-app-worktree-discovery.md`, "Implemented Decision").
- The stdio client (`codex_operator/Sources/OperatorDesktop/Repositories/CodexAppServerStdioClient.swift`)
  already speaks `thread/start` and `turn/start` as separate methods — so
  "send another turn to an existing thread" is plausibly just `turn/start`
  with the saved thread id, but this has never been exercised by Operator.
- PRD conventions: PRDs live at `.scratch/<slug>/PRD.md` with a
  `Status: ...` line at the top; see `.scratch/add-project-ux/PRD.md` as the
  structural exemplar (Problem Statement / Solution / User Stories /
  Implementation Decisions / Out of Scope). Triage statuses available:
  `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`,
  `wontfix` (CLAUDE.md).

## Commands you will need

| Purpose | Command (from `codex_operator/`) | Expected on success |
|---------|----------------------------------|---------------------|
| Baseline sanity | `swift test`              | exit 0              |

(No code changes in this plan; the test run only proves you didn't make any.)

## Scope

**In scope** (the only files you should create/modify):
- `.scratch/follow-up-runs/PRD.md` (create)

**Out of scope** (do NOT touch):
- All Swift source and test files — this spike changes no code.
- `docs/operator-descktop-mvp.md` — the MVP PRD is a historical record;
  supersede it in the new PRD, don't edit it.
- Scheduling/cron, PR creation, GitHub integration — stay out of those
  directions entirely; they are separate decisions.

## Git workflow

- Branch: `advisor/003-follow-up-runs-spike`
- One commit, e.g. `docs: add follow-up runs PRD`.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Gather the constraints

Read, in order: `docs/operator-descktop-mvp.md` (state model, out-of-scope
list), `codex_operator/Sources/OperatorDesktop/Models/TaskLifecycle.swift`,
`OperatorStore.swift` run-recording functions (`recordStartedRun`,
`completeStartedRun`, `recordFailedRun`), and
`docs/codex-app-worktree-discovery.md`. If
`docs/running-task-recovery-spike.md` exists (output of plan 001), read it —
its findings about app-server thread APIs directly constrain option B below.

**Verify**: you can state, in the PRD, why a second successful run is
currently impossible (which guard, in which file).

### Step 2: Write `.scratch/follow-up-runs/PRD.md`

Status line: `Status: needs-triage` (a human picks it up from triage).
Follow the structure of `.scratch/add-project-ux/PRD.md`. The PRD must
evaluate at least these three options against the MVP's design values
(Operator triggers; Codex App owns the work):

- **Option A — Duplicate as new task**: a "Duplicate to Ready" action on
  Done/Running tasks copies title/prompt/repo/effort into a fresh Ready task,
  optionally linked to the original. Preserves one-task-one-thread purity;
  costs thread continuity.
- **Option B — Follow-up turn on the same thread**: a Done task gets a
  "Send follow-up" action that issues a new `turn/start` on the saved thread
  in the saved worktree. Preserves continuity; complicates the state model
  (Done→Running again? second prompt stored where?) and duplicates what
  Codex App's own chat box already does well.
- **Option C — Status quo plus deep link** (do-nothing baseline): document
  that follow-ups happen in Codex App, and make that path excellent. Must be
  argued against, not ignored.

For the recommended option, the PRD must specify: the new state diagram (in
the same `text` block style as the MVP PRD), what happens to the
one-successful-run invariant and the run/worktree/thread relationship, what
becomes mutable, and an explicit out-of-scope list. User stories follow the
"As a developer, I want X, so that Y" style of the existing PRDs.

**Verify**: file exists; contains a `Status:` first line, all three options
with at least one stated trade-off each, exactly one recommendation, and a
state-diagram `text` block.

### Step 3: Confirm no code was touched

**Verify**: `git status` shows only `.scratch/follow-up-runs/PRD.md` (and
`plans/README.md` if you updated your status row); `swift test` from
`codex_operator/` → exit 0.

## Test plan

Not applicable (documentation-only). The done criteria below are the gate.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `.scratch/follow-up-runs/PRD.md` exists, first line matches `Status: `
- [ ] `grep -c "Option" .scratch/follow-up-runs/PRD.md` ≥ 3
- [ ] PRD contains a recommendation section naming exactly one option
- [ ] `git status` shows no modified Swift files
- [ ] `swift test` exits 0
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- The lifecycle no longer matches the "Current state" excerpts (someone
  already started loosening the one-shot constraint).
- You cannot determine from code + docs how a second turn would be sent
  (e.g. the stdio client's `turn/start` requires state that isn't persisted)
  — record the open question in the PRD as `needs-info` and say so in your
  report rather than guessing the API.
- You find yourself writing Swift code. This plan produces a document.

## Maintenance notes

- The implementation plan that follows this PRD should be written only after
  a human triages the PRD (per the repo's triage flow).
- Whichever option wins, `TaskLifecyclePolicyTests` is where the new
  transitions get characterized first — note that in the PRD's testing
  section.
- Interaction with plan 001: manual "Mark as Done" plus follow-up sends can
  create a Done task whose last turn never actually completed; the PRD
  should mention this edge.
