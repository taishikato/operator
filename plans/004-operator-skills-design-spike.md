# Plan 004: Design spike — "operator skills": let coding agents drive Operator via a first-class CLI

> **Executor instructions**: This is a design spike. You will produce a PRD
> document (and optionally a draft skill file), not production code. Follow
> the steps, honor the STOP conditions, and when done update the status row
> for this plan in `plans/README.md` — unless a reviewer dispatched you and
> told you they maintain the index.
>
> **Drift check (run first)**:
> `git diff --stat 022a616..HEAD -- codex_operator/Sources/OperatorDesktop codex_operator/Package.swift docs/`
> If the store, lifecycle, or trigger code changed since this plan was
> written, compare the "Current state" excerpts against the live code before
> proceeding; on a mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: M (spike + small throwaway experiments; implementation is a future plan)
- **Risk**: LOW (no production code changes)
- **Depends on**: none hard. Soft: plan 001 (running-task recovery) defines
  what happens to a run left in `running` state, which constrains the CLI
  `send` semantics; plan 003 (follow-up sends) may add verbs to the surface.
  Read both plans' outputs if they exist, but do not block on them.
- **Category**: direction
- **Planned at**: commit `022a616`, 2026-06-10

## Why this matters

Operator is a local Kanban board that triggers Codex; today the only client
is the SwiftUI app. The maintainer wants coding agents (Codex, Claude Code)
to interact with Operator directly — add tasks, inspect tasks, send tasks,
manage lifecycle — via local agent skills, so that an agent can say "file
this follow-up as an Operator task" or "send task X to Codex" without a
human clicking the board. The core design question is the interface: a
first-class CLI, skills that poke Operator's SQLite directly, an MCP/server
interface, or a combination. This spike settles that decision and writes the
PRD before anyone builds the wrong interface.

## Recommended direction (validate, don't blindly accept)

**Combination of options 1 + skill packaging: a first-class `operator` CLI
(new `executableTarget` in the existing Swift package, reusing the
`OperatorDesktop` library), plus thin agent skills that call that CLI.
Reject direct DB/file manipulation by skills. Defer MCP.** Rationale, from
the codebase:

- All domain invariants live in the `OperatorDesktop` library target, not in
  the app: `TaskLifecyclePolicy` guards every transition
  (`codex_operator/Sources/OperatorDesktop/Models/TaskLifecycle.swift:54-100`),
  `OperatorStore` owns schema + migrations
  (`codex_operator/Sources/OperatorDesktop/Persistence/OperatorStore.swift:562-617`),
  and `CodexTriggerService.sendTaskToCodex` orchestrates worktree + app-server
  (`codex_operator/Sources/OperatorDesktop/Repositories/CodexTriggerService.swift:158-207`).
  The trigger path is Foundation + GRDB only (no AppKit), so a CLI target can
  reuse it wholesale. `Package.swift` already exposes the library product and
  a second executable target is a ~10-line addition.
- Direct SQLite manipulation by skills (option 2) would bypass
  `TaskLifecyclePolicy`, the one-success-per-task partial unique index
  (`OperatorStore.swift:604`), and three existing migrations — every schema
  change would silently break every installed skill. Reject; record the
  rejection in the PRD.
- MCP (option 3) adds a server lifecycle, transport, and schema for no
  capability the CLI doesn't give: both Codex and Claude Code skills can
  shell out, and a CLI is human-debuggable. An MCP server wrapping the same
  library is an easy later addition; note it as future work, don't build it.
- Operator already spawns `codex app-server` itself over stdio and does not
  require Codex App to be running (`docs/operator-descktop-mvp.md:123-126`),
  so a headless `operator send` is feasible.

The spike's job is to validate the two technical risks below, decide the
open questions, and write the PRD.

## Current state

- `codex_operator/Package.swift` — Swift 6.2 package, macOS 26, GRDB 7.10+;
  products: `OperatorDesktop` library, `Operator` app executable, tests.
- `codex_operator/Sources/OperatorDesktop/Persistence/OperatorStore.swift` —
  GRDB store. **Risk 1 lives here**: line 68 is
  `dbQueue = try DatabaseQueue(path: databaseURL.path)` with default
  configuration — no WAL, no `busyTimeout`. Two processes (running app + CLI)
  writing concurrently will hit `SQLITE_BUSY`. Tables: `repositories`,
  `tasks`, `runs`. DB path: `~/Library/Application Support/Operator/operator.sqlite`
  (`OperatorAppBootstrap.swift:4-20`).
- Change propagation is **in-process only**: `OperatorStore.changes` is a
  Combine `PassthroughSubject` fired by the store's own write methods
  (`OperatorStore.swift:57-61, 458-460`), consumed by
  `BoardView.swift:72` and `ArchivedView.swift:62`. **Risk 2**: a CLI write
  will not refresh a running app's board.
- Task model (`TaskLifecycle.swift`): statuses `ready / review / done /
  archived` (`review` renders as the "Running" column). Only `ready` is
  editable/sendable; `done` is reached automatically when the Codex turn
  completes; `archive` is the only user-driven removal. There is no hard
  delete, by PRD decision (`docs/operator-descktop-mvp.md:97`).
- `CodexTriggerService.swift:193-196`: after a successful trigger the service
  spawns an in-process `Task` that waits for turn completion and then calls
  `store.completeStartedRun`. A short-lived CLI process that exits after
  triggering would strand the run in `running` (task stuck in the Running
  column). Plan 001 (`plans/001-running-task-recovery.md`) addresses recovery
  for the app; the CLI design must not assume it landed.
- Repo conventions for the deliverable: PRDs live at
  `.scratch/<feature-slug>/PRD.md` with a `Status:` line near the top
  (`docs/agents/issue-tracker.md`); triage statuses are `needs-triage`,
  `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. Use
  `.scratch/operator-desktop-mvp/PRD.md` (or `docs/operator-descktop-mvp.md`)
  as the structural exemplar: Problem Statement / Solution / User Stories /
  Implementation Decisions / Testing Decisions / Out of Scope.
- `webapp/` is an experimental Cursor-SDK app superseded by the desktop
  direction (`docs/operator-descktop-mvp.md:236`). It is irrelevant to this
  spike; do not design for it.

## Commands you will need

| Purpose | Command (run in `codex_operator/`) | Expected on success |
|---------|------------------------------------|---------------------|
| Build   | `swift build`                      | exit 0 |
| Tests   | `swift test`                       | all pass |
| Inspect live DB schema (read-only) | `sqlite3 "file:$HOME/Library/Application Support/Operator/operator.sqlite?mode=ro" .schema` | DDL for 3 tables |

## Scope

**In scope** (the only files you create/modify):
- `.scratch/operator-skills/PRD.md` (create)
- `.scratch/operator-skills/spike-notes.md` (create — experiment evidence)
- `plans/README.md` (status row update)
- Throwaway experiment code under `/tmp` or `.scratch/operator-skills/` only.

**Out of scope** (do NOT touch):
- Anything under `codex_operator/Sources/` or `Tests/` — this spike ships no
  production code.
- The user's live database at `~/Library/Application Support/Operator/` —
  open it read-only if at all; run write experiments against a temp DB.
- `webapp/` entirely.
- Building the MCP server, scheduling, or remote access of any kind.

## Steps

### Step 1: Read the source of truth

Read, in order: `docs/operator-descktop-mvp.md`,
`codex_operator/README.md`, `OperatorStore.swift`, `TaskLifecycle.swift`,
`CodexTriggerService.swift`, `OperatorAppBootstrap.swift`,
`docs/agents/issue-tracker.md`, and `plans/001-*.md` / `plans/003-*.md` if
their status is DONE (their outputs constrain send semantics and verbs).

**Verify**: you can state from memory the four task statuses, the DB path,
and why a fire-and-exit CLI `send` strands a run.

### Step 2: Experiment — cross-process SQLite behavior (Risk 1)

In a temp directory, write a small throwaway Swift script (or use two
`sqlite3` shells) against a **copy** of the schema (create it via
`OperatorStore(databaseURL:)` from a scratch Swift package, or replay the
`.schema` DDL):

1. Open the DB from two processes; have one hold a write transaction while
   the other writes. Record the failure mode with default GRDB
   `DatabaseQueue` config (expect `SQLITE_BUSY`).
2. Repeat with `PRAGMA journal_mode=WAL` and a busy timeout. Record whether
   concurrent app+CLI writes become safe in practice.

Write findings into `.scratch/operator-skills/spike-notes.md`. The PRD's
concurrency decision must cite this evidence.

**Verify**: spike-notes.md contains both experiment results with the exact
pragmas/config used.

### Step 3: Decide the open design questions

Record each decision in the PRD's Implementation Decisions, with one line of
rationale. The questions, with recommended defaults:

1. **Concurrency**: shared `OperatorStore` init gains WAL + busyTimeout so
   app and CLI can coexist (recommended, pending Step 2 evidence). Both
   processes use the same `OperatorStore` code — never raw SQL from the CLI.
2. **UI refresh on external writes**: recommend the app polls
   `PRAGMA data_version` on a coarse timer plus refresh on app activation;
   alternatives (DistributedNotificationCenter posted by the CLI, file
   watcher on the DB) should be listed and rejected/accepted explicitly.
3. **CLI verb surface (MVP)**: recommend
   `operator repo list`,
   `operator task add --repo <name|id> --title <t> [--prompt <p>|--prompt-file <f>] [--effort low|medium|high|xhigh]`,
   `operator task list [--repo ...] [--status ...]`,
   `operator task show <id>`,
   `operator task archive <id>`,
   `operator task send <id> [--wait]`,
   `operator run list --task <id>`.
   "Update status" requests map ONLY to lifecycle-legal transitions
   (archive; everything else is automatic or forbidden) — the CLI must not
   invent transitions the board forbids.
4. **`send` semantics**: recommend default `--wait` (process stays alive
   until turn completion, mirroring the app) with `--no-wait` documented as
   leaving the task in Running until recovery (plan 001) or the app handles
   it. Decide explicitly; this is the riskiest verb.
5. **Output format**: human text by default, `--json` on every verb with a
   stable schema (agents parse this; document the schema in the PRD).
6. **Binary distribution**: recommend a third target in `Package.swift`
   (`executableTarget` `operator-cli` depending on `OperatorDesktop`),
   installed by `script/` alongside the app bundle; decide the install path
   (e.g. symlink into `/usr/local/bin` vs documented `swift run` path).
7. **Skill packaging**: where do the skills live and what do they contain?
   Recommend: a `skills/` directory in this repo with one skill per agent
   ecosystem (Claude Code `SKILL.md`; Codex equivalent per its current skill
   conventions — verify what Codex supports at spike time rather than
   assuming). Skills are thin: they document the CLI contract and when to
   use it; all logic stays in the CLI.
8. **Exit codes / error contract**: map `TaskLifecycleError` and
   `OperatorStoreError` cases to distinct exit codes or a `--json` error
   object, so agents can branch on "task is immutable" vs "not found".

### Step 4: Write the PRD

Create `.scratch/operator-skills/PRD.md` with `Status: ready-for-human` near
the top (the maintainer reviews direction decisions). Structure it like the
exemplar: Problem Statement / Solution / User Stories / Implementation
Decisions / Testing Decisions / Out of Scope. Requirements:

- The Solution section states the chosen architecture (expected: CLI target
  reusing `OperatorDesktop` + thin skills; MCP deferred; direct DB access by
  skills rejected) and cites the spike-notes evidence for the concurrency
  decision.
- Implementation Decisions cover every question from Step 3.
- Testing Decisions follow the repo's style (behavioral, fake app-server
  client for `send`, temp databases — mirror `docs/operator-descktop-mvp.md`
  "Testing Decisions").
- Out of Scope explicitly lists: MCP server, remote/network access,
  scheduling, hard delete, any transition not in `TaskLifecyclePolicy`,
  webapp integration.
- Do not contradict the MVP PRD's safety stances (no automatic worktree
  cleanup, no hard delete, Operator never claims Codex success/failure). If
  a CLI verb seems to need one of these, that's a finding for the PRD's open
  questions, not a decision to override.

**Verify**: every Step 3 question has a corresponding decision line;
`grep -c "Status:" .scratch/operator-skills/PRD.md` ≥ 1.

### Step 5: Update the index

Set plan 004's status in `plans/README.md` to DONE with a one-line pointer to
the PRD path.

## Test plan

Spike — no production tests. The deliverable's quality gate is the Done
criteria below; the PRD itself must contain Testing Decisions for the future
implementation plan.

## Done criteria

ALL must hold:

- [ ] `.scratch/operator-skills/PRD.md` exists with a `Status:` line and all
      six exemplar sections.
- [ ] `.scratch/operator-skills/spike-notes.md` records the two-process
      SQLite experiment (default config and WAL+timeout) with observed
      results.
- [ ] All eight Step 3 questions have explicit decisions in the PRD.
- [ ] `git status` shows no modifications under `codex_operator/` or
      `webapp/`.
- [ ] `swift test` (run in `codex_operator/`) still passes — proves the spike
      touched no production code.
- [ ] `plans/README.md` row for 004 updated.

## STOP conditions

Stop and report back (do not improvise) if:

- `OperatorStore.swift` no longer matches the excerpts (e.g. WAL or
  cross-process support already landed) — the spike's Risk 1 may be moot;
  report what changed instead of re-deciding it.
- The Step 2 experiment shows WAL + busy timeout still cannot make
  app+CLI concurrent writes safe — the architecture recommendation (shared
  SQLite, two writers) collapses; report the evidence and the fallback
  options (CLI talks to the app via IPC; or CLI only works while app is
  closed) rather than picking one unilaterally.
- You find that Codex's current skill mechanism cannot invoke a local CLI —
  the "thin skill over CLI" premise breaks for the primary target agent;
  report what Codex skills can actually do.
- Deciding any Step 3 question would require contradicting an MVP PRD safety
  stance (no hard delete, no automatic worktree cleanup, no success
  classification).

## Maintenance notes

- The implementation plan that follows this PRD will touch
  `Package.swift`, add a CLI target, and likely modify `OperatorStore.init`
  (WAL/busyTimeout) — that store change affects the app too and needs its own
  migration-safety check (WAL leaves `-wal`/`-shm` files next to the DB).
- Plans 001 and 003 interact: 001 defines recovery for stranded `running`
  runs (the CLI `--no-wait` case), 003 may add follow-up-turn verbs to the
  CLI surface. Whoever implements the CLI should re-read both.
- A future MCP server should wrap the same `OperatorDesktop` library (or the
  CLI), never the DB directly — the PRD should say this so it survives as a
  recorded decision.
