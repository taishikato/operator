# PRD: Operator skills — agent-facing `operator` CLI + thin agent skills

Status: ready-for-human

> Produced by plan 004 (design spike). Evidence for the concurrency and send
> decisions lives in `.scratch/operator-skills/spike-notes.md`. At the
> maintainer's request the implementation was executed in the same session as
> this spike, so "ready-for-human" review doubles as code review of that
> implementation.

## Problem Statement

Operator's only client is the SwiftUI app, so coding agents (Codex, Claude
Code) cannot file follow-ups as Operator tasks, inspect the board, or send a
ready task to Codex without a human clicking the UI. Agents need a local,
scriptable interface that preserves every domain invariant the board
enforces — task lifecycle, one-success-per-task, no hard delete — without
each agent reimplementing (and inevitably breaking) those rules.

## Solution

A first-class `operator` CLI shipped as a new executable target in the
existing Swift package, reusing the `OperatorDesktop` library for all domain
logic, plus thin agent skills (Agent Skills standard `SKILL.md`, one source
serving both Claude Code and Codex) that document when and how to call that
CLI. Specifically:

- **CLI target `operator-cli`** (installed/symlinked as `operator`) linking
  `OperatorDesktop`. Every write goes through `OperatorStore` and
  `TaskLifecyclePolicy`; the CLI contains no SQL and no lifecycle rules of
  its own. `task send` reuses `CodexTriggerService` +
  `CodexAppServerStdioClient`, which already work headless (Operator spawns
  `codex app-server` itself; Codex App need not run).
- **Shared store hardening**: `OperatorStore` opens SQLite in WAL mode with
  a busy timeout so the app and the CLI can write concurrently. Spike
  evidence: with today's default config a second process fails immediately
  with `SQLITE_BUSY (5)`; with WAL + busy_timeout=5000 the second writer
  blocks ~2s and succeeds, and cross-process reads proceed during a held
  write transaction (spike-notes Experiments 1–2).
- **External-change refresh**: the app polls `PRAGMA data_version` on a
  coarse timer and fires the existing `OperatorStore.changes` publisher when
  it moves, so CLI writes appear on a running board (spike-notes
  Experiment 3).
- **Thin skills**: `skills/operator/SKILL.md` in this repo, installable into
  `~/.claude/skills/` and `~/.codex/skills/`. Skills document the CLI
  contract (verbs, `--json` schema, exit codes) and when to use it; all
  logic stays in the CLI.

**Rejected: skills manipulating SQLite directly.** That would bypass
`TaskLifecyclePolicy`, the one-success-per-task partial unique index
(`OperatorStore.swift` migrations), and three existing migrations; every
schema change would silently break every installed skill.

**Deferred: MCP server.** It adds a server lifecycle, transport, and schema
for no capability the CLI doesn't give — both Codex and Claude Code skills
can shell out, and a CLI is human-debuggable. A future MCP server must wrap
the same `OperatorDesktop` library (or the CLI), never the DB directly.

## User Stories

1. As a coding agent finishing unrelated work, I want to file a follow-up as
   an Operator task (`operator task add`), so the human's board captures it
   without interrupting them.
2. As a coding agent, I want to list repositories and tasks with `--json`,
   so I can resolve names to IDs and branch on task status reliably.
3. As a coding agent, I want to send a ready task to Codex
   (`operator task send`), so queued work starts without a human clicking
   the board.
4. As a coding agent, I want lifecycle-illegal requests (edit a Running
   task, send a Done task) to fail with a distinct exit code, so I can
   explain the refusal instead of retrying blindly.
5. As the maintainer, I want the running app's board to reflect CLI writes
   within seconds, so agent-filed tasks are visible without a restart.
6. As the maintainer, I want the CLI to enforce exactly the board's rules,
   so no client can corrupt task history.

## Implementation Decisions

Numbered per plan 004 Step 3.

1. **Concurrency**: `OperatorStore.init` configures GRDB with
   `busyMode = .timeout(5)` and `PRAGMA journal_mode = WAL` (applied via
   `Configuration.prepareDatabase`), shared by app and CLI. Evidence:
   spike-notes Experiments 1–2 (default config → `SQLITE_BUSY (5)` and a
   lost write; WAL+timeout → blocked ~2s then succeeded). Both processes use
   the same `OperatorStore` code — never raw SQL from the CLI. WAL leaves
   `-wal`/`-shm` companions next to `operator.sqlite`; WAL is persistent in
   the DB header, and SQLite falls back gracefully for read-only opens.
2. **UI refresh on external writes**: the app polls `PRAGMA data_version`
   every 2s via `OperatorStore.startObservingExternalChanges()` and fires
   the existing `changes` publisher on movement (Experiment 3: the pragma
   moves only on *other* connections' commits, so in-process writes don't
   double-fire). Rejected: `DistributedNotificationCenter` posted by the CLI
   (couples every future writer to a notification contract; silently wrong
   if a writer forgets) and an FSEvents/dispatch-source file watcher on the
   DB (WAL makes file events noisy and checkpoint-dependent). Polling one
   pragma on one existing connection is cheap and writer-agnostic.
3. **CLI verb surface (MVP)**:
   `operator repo list`;
   `operator repo add <path>` (added after dogfooding: the very first
   skill-driven session stalled because its repo wasn't registered and only
   the app could register one; reuses `RepositoryRegistrationService`, so
   validation and default-branch inference match the app);
   `operator task add --repo <name|id> --title <t> [--prompt <p> | --prompt-file <f>] [--effort low|medium|high|xhigh]`;
   `operator task list [--repo <name|id>] [--status ready|review|done|archived]`;
   `operator task show <id>`;
   `operator task archive <id>`;
   `operator task send <id>`;
   `operator run list --task <id>`.
   "Update status" maps ONLY to lifecycle-legal transitions — i.e. archive.
   Everything else is automatic (review→done) or forbidden; the CLI invents
   no transition the board forbids. Repo *editing* (default-branch fixes)
   stays in the app's Settings.
4. **`send` semantics**: `send` always waits for turn completion (process
   stays alive, mirroring the app), with `--timeout <seconds>` as an escape
   hatch that exits distinctly while the turn may still be aborted by
   process exit. **`--no-wait` is not offered**: the spawned
   `codex app-server` is a child of the CLI, so exiting after the trigger
   kills the turn itself — the plan's "stranded run until recovery" framing
   undersold the damage (spike-notes Finding 3). Agents that don't want to
   block should run the command in their own background facility. Known
   limitation: launching the app mid-send prematurely completes the CLI's
   run via `recoverInterruptedRuns()` (task shows Done early; thread and
   worktree unharmed). Follow-up direction: run ownership (PID/heartbeat
   column) so recovery skips live foreign runs — schema change, deferred.
   The CLI does not use the thread-visibility controller (hiding threads is
   app UX; a CLI crash would otherwise strand hidden threads).
5. **Output format**: human-readable text by default; `--json` on every verb
   with a stable schema (below). Errors with `--json` go to stdout as
   `{"error":{"code":<string>,"message":<string>}}`; exit code still set.
6. **Binary distribution**: new `executableTarget` `OperatorCLI` (product
   `operator-cli`) in `Package.swift`, depending on `OperatorDesktop` and
   apple/swift-argument-parser. The product cannot be named `operator`: the
   existing `Operator` app product would collide on macOS's
   case-insensitive filesystem (spike-notes Finding 5).
   `script/install_cli.sh` builds release and symlinks
   `~/.local/bin/operator` (no sudo; prints a PATH hint), which also matches
   what the skills tell agents to invoke.
7. **Skill packaging**: one skill source at `skills/operator/SKILL.md`
   following the Agent Skills standard (name + description frontmatter),
   which both Claude Code and Codex consume natively (Codex discovers
   `~/.codex/skills` and `.codex/skills`; Claude Code `~/.claude/skills` and
   `.claude/skills` — verified at spike time, spike-notes Finding 4).
   `script/install_skills.sh` symlinks the skill into both personal
   directories so agents working in *any* repo can file Operator tasks.
   Skills are thin: contract + when-to-use; no DB paths, no SQL, no
   lifecycle logic.
8. **Exit codes / error contract**: distinct codes so agents can branch
   without parsing prose; identical `code` strings in `--json` errors.

   | Exit | `code` (JSON) | Source |
   |------|---------------|--------|
   | 0    | —             | success |
   | 2    | `notFound`    | `OperatorStoreError.repositoryNotFound` / `.taskNotFound`, unknown run/task IDs, ambiguous/unknown `--repo` |
   | 3    | `lifecycleViolation` | `TaskLifecycleError` (immutable task, forbidden transition, already has a successful run) |
   | 4    | `codexUnavailable`   | Codex binary not found/misconfigured (`CodexBinaryConfigurationError`) |
   | 5    | `sendFailed`  | trigger attempt recorded as failed (`runs` row with `triggerFailed`) |
   | 6    | `timeout`     | `send --timeout` elapsed before turn completion |
   | 7    | `invalidRepository` | `repo add` path is not a usable Git repository (`RepositoryRegistrationError`) |
   | 8    | `alreadyRegistered` | `repo add` path already registered (`OperatorStoreError.repositoryPathAlreadyRegistered`; message carries the existing id) |
   | 64   | `usage`       | argument-parsing/validation errors (ArgumentParser default) |
   | 70   | `internal`    | unexpected store/IO errors |

   `--json` entity schemas (dates ISO 8601, IDs uppercase UUID strings):
   - repository: `{"id","name","path","defaultBranch","createdAt","updatedAt"}`
   - task: `{"id","repositoryID","title","prompt","reasoningEffort","status","createdAt","updatedAt"}`
   - run: `{"id","taskID","repositoryID","status","worktreePath","baseBranch","baseRef","codexThreadID","codexThreadURL","errorMessage","createdAt","completedAt"}`
   List verbs emit a JSON array; singular verbs emit one object. New fields
   may be added; existing fields/values only change with a documented major
   bump in the skill.

## Testing Decisions

Mirroring the MVP PRD's behavioral style:

- Store concurrency: a behavioral test opens two `OperatorStore` instances
  on the same temp-file DB (two connections — the same locking domain as
  two processes) and verifies a write from the second succeeds while the
  first holds work, and that WAL mode is actually active
  (`PRAGMA journal_mode` returns `wal`).
- External-change observation: write through a second store instance and
  assert the first store's `changes` publisher fires from polling; assert
  in-process writes do not double-fire via the poller.
- CLI command logic lives in a testable core (`OperatorCLICore` library
  target); tests drive commands as functions against temp databases and a
  fake `CodexAppServerClient` (as `CodexTriggerServiceTests` does), never a
  spawned binary or real Codex.
- Verb tests verify: lifecycle-illegal operations map to exit 3 /
  `lifecycleViolation`; unknown IDs map to exit 2; `--json` output matches
  the documented schema exactly (golden assertions on keys); `task add`
  resolves `--repo` by name and by ID; `send` passes the prompt verbatim
  and waits for the fake turn completion before returning.
- No UI tests added; board refresh is covered at the store level.

## Out of Scope

- MCP server (future work; must wrap `OperatorDesktop` or the CLI, never the DB).
- Remote/network access of any kind; the CLI is local-only.
- Scheduling, cron, queues.
- Hard delete (archive remains the only removal), automatic worktree
  cleanup, and Codex success/failure classification — MVP PRD safety
  stances stand.
- Any transition not in `TaskLifecyclePolicy` (no review→ready, no rerun,
  no done→ready).
- Repo registration/edit via CLI.
- Follow-up turns / rerun verbs (plan 003's territory; the CLI surface can
  grow verbs once 003 lands).
- `send --no-wait` / detached daemon sends (see Implementation Decision 4).
- webapp integration (superseded direction).

## Open Questions

- Should `recoverInterruptedRuns()` learn run ownership (PID/heartbeat) so
  an app launch doesn't prematurely complete a CLI-owned in-flight run?
  Recommended follow-up; needs a migration.
- ~~Should `repo add` exist for fully headless setups once agents demand
  it?~~ Resolved 2026-06-12: yes — the first skill-driven session stalled on
  an unregistered repo, so `repo add` shipped (see decision 3).
