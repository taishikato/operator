# Spike notes: operator skills (plan 004)

Date: 2026-06-12. Executor: Claude Code. Environment: macOS (Darwin 25.5.0),
sqlite3 3.51.0 (2025-06-12 build).

## Drift check (plan 004 preamble)

`git diff --stat 022a616..HEAD -- codex_operator/Sources/OperatorDesktop codex_operator/Package.swift docs/`
showed additive changes only (Codex thread visibility work + run recovery):

- `OperatorStore.swift` gained `runningRuns()`; line 68 is still
  `dbQueue = try DatabaseQueue(path: databaseURL.path)` with default
  configuration — **Risk 1 unchanged**.
- `OperatorStore.changes` is still an in-process `PassthroughSubject` —
  **Risk 2 unchanged**.
- `CodexTriggerService` gained optional thread-visibility hiding and
  `recoverInterruptedRuns()`, which the app calls at launch
  (`OperatorApp.swift:34`). This is plan 001's recovery behavior, landed
  early: any run still `running` at app launch is completed and its hidden
  thread revealed. This materially constrains the CLI `send` semantics (see
  finding 3).

No STOP condition triggered.

## Experiment 1 — two-process writes, default config (Risk 1)

Setup: temp DB at `/tmp/operator-skills-spike.*/test.sqlite` created from the
live DB's `.schema` (read-only dump; live DB untouched). Default journal mode
confirmed as `delete`. GRDB's `DatabaseQueue` default maps to the same
behavior: `Configuration.busyMode = .immediateError` (GRDB
`Configuration.swift:331`) and no WAL.

Procedure: process A runs `BEGIN IMMEDIATE; INSERT …; sleep 3; COMMIT;`
while process B (`.timeout 0`, mirroring `.immediateError`) attempts an
INSERT 0.7s in.

Result: **process B failed immediately** with
`Error: stepping, database is locked (5)` — exit code 5 = `SQLITE_BUSY`.
Process B's row was lost. Conclusion: with today's `OperatorStore` config, a
CLI writing while the app writes (or vice versa) fails hard.

## Experiment 2 — WAL + busy_timeout (Risk 1 mitigation)

Same setup after `PRAGMA journal_mode=WAL;`. Process A holds the same 3s
write transaction; process B uses `.timeout 5000` (busy_timeout = 5000 ms).

Results:

- Process B **blocked ~2s and then succeeded** (exit 0); both rows present.
- A concurrent reader (`.timeout 0`) **succeeded during** a held write
  transaction — WAL allows cross-process reads while writing.
- WAL leaves `test.sqlite-wal` / `test.sqlite-shm` next to the DB
  (migration-safety note from the plan confirmed: the app data dir gains two
  files).

Conclusion: WAL + busy timeout makes app+CLI concurrent writes safe in
practice for Operator's short transactions. The implementation should set
`Configuration.busyMode = .timeout(…)` and `PRAGMA journal_mode = WAL` in
`OperatorStore.init`, shared by both processes.

## Experiment 3 — external-change detection via `PRAGMA data_version` (Risk 2)

On a persistent connection, `PRAGMA data_version` returned `3`; after an
external process committed an INSERT, the same connection returned `4`.
(Note: the value only moves for commits made by *other* connections, so the
app can poll it cheaply on a timer and fire the existing `changes` publisher
when it moves.)

## Finding 3 — `send --no-wait` is not just "stranded run", it kills the turn

`CodexAppServerStdioClient` spawns `codex app-server` as a child of the
calling process (stdio transport). The recovery comment in
`CodexTriggerService.swift:242-244` states the invariant: "The spawned
app-server dies with the app, so these turns cannot still be running." A CLI
that exits right after the trigger is accepted therefore **aborts the Codex
turn itself**, not merely the bookkeeping. So the plan's recommended
"`--no-wait` documented as leaving the task in Running until recovery" is
unsafe-by-design: the recovered task would look Done while Codex did almost
no work. Decision recorded in the PRD: `send` always waits; no `--no-wait`
in the MVP.

Corollary: if the app launches while a CLI `send` is mid-turn, the app's
`recoverInterruptedRuns()` will prematurely complete the CLI's run (it
cannot distinguish a foreign live process from a dead one). Recorded in the
PRD as a known limitation with a follow-up direction (run ownership
PID/heartbeat), not fixed in this iteration.

## Finding 4 — Codex skill mechanism (STOP-condition check)

Codex adopted the open Agent Skills standard: a skill is a directory with a
`SKILL.md` (name + description frontmatter), discovered from `~/.codex/skills`
(personal) or `.codex/skills` (per-repo), with implicit invocation from the
description — same format Claude Code uses. Codex skills can shell out to
local CLIs. The "thin skill over CLI" premise holds; one skill source can
serve both ecosystems. (Sources: developers.openai.com/codex/skills;
openai/skills catalog.)

## Finding 5 — executable naming collision

`Package.swift` already ships an executable product named `Operator` (the
app). On macOS's default case-insensitive filesystem a new product literally
named `operator` would collide with it in `.build/<config>/`. The CLI target
is therefore `operator-cli`; installation symlinks it as `operator`.
