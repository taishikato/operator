---
name: operator
description: Use when asked to file, list, inspect, archive, or send tasks on the user's Operator board (the local macOS Kanban app that triggers Codex), or when work surfaces a follow-up worth queueing for Codex — e.g. "add this to my Operator board", "file a follow-up task", "send task X to Codex", "what's on my board?".
---

# Operator board CLI

Operator is a local macOS Kanban board that sends coding tasks to Codex.
Drive it with the `operator` CLI only — never read or write its SQLite
database directly. The CLI runs the same domain code as the app, so every
lifecycle rule the board guarantees is enforced for you.

## Setup check

Run `operator --help`. If the binary is missing, install it from the
operator repo: `codex_operator/script/install_cli.sh` (symlinks into
`~/.local/bin`).

## Commands

Add `--json` to every command you parse; human output is not stable.

| Action | Command |
|--------|---------|
| List repositories | `operator repo list --json` |
| Create a task | `operator task add --repo <name\|id> --title <t> --prompt <p> [--effort low\|medium\|high\|xhigh] --json` |
| Multi-line prompt | `operator task add ... --prompt-file <path> --json` |
| List tasks | `operator task list [--repo <name\|id>] [--status ready\|review\|done\|archived] --json` |
| Show one task (with prompt) | `operator task show <task-id> --json` |
| Archive a task | `operator task archive <task-id> --json` |
| Send a Ready task to Codex | `operator task send <task-id> [--timeout <s>] --json` |
| List a task's trigger attempts | `operator run list --task <task-id> --json` |

The prompt is sent to Codex verbatim — write it as a complete, standalone
instruction. Resolve `--repo` names via `repo list` first; ambiguous names
require the id.

## Lifecycle rules (enforced — don't fight them)

- Statuses: `ready` → `review` (the board's "Running" column) → `done`;
  `archived` removes a task from the board.
- Only `ready` tasks can be sent. One successful send per task; no rerun.
- `review` → `done` happens automatically when the Codex turn completes.
- Archive is the only manual status change and the only removal — there is
  no delete and no way to move a task back to `ready`.

## `task send` blocks until the Codex turn finishes

The Codex app-server runs as a child of the CLI, so **exiting early
(Ctrl-C, `--timeout`) aborts the Codex turn itself**. Expect minutes of
runtime; use your own background-execution facility if you must not block.
There is deliberately no `--no-wait`. On success the task lands in `done`
with the Codex thread recorded (`run list` shows `codexThreadID`).

## Exit codes and errors

| Exit | JSON `error.code` | Meaning / what to do |
|------|-------------------|----------------------|
| 0 | — | success |
| 2 | `notFound` | unknown repo/task id — re-check with `repo list` / `task list` |
| 3 | `lifecycleViolation` | the board forbids this (immutable task, already sent, bad transition) — report it, don't retry |
| 4 | `codexUnavailable` | Codex binary missing/misconfigured — user must fix Codex setup |
| 5 | `sendFailed` | trigger failed (e.g. worktree/git error); task stays `ready`, retry is allowed |
| 6 | `timeout` | `--timeout` elapsed; the turn was aborted by exiting |
| 64 | `usage` | bad arguments |
| 70 | `internal` | unexpected error |

With `--json`, errors print `{"error":{"code":"...","message":"..."}}` on
stdout and the exit code is still set.

## JSON shapes (stable keys, ISO 8601 dates)

- repository: `id`, `name`, `path`, `defaultBranch`, `createdAt`, `updatedAt`
- task: `id`, `repositoryID`, `title`, `prompt`, `reasoningEffort`, `status`, `createdAt`, `updatedAt`
- run: `id`, `taskID`, `repositoryID`, `status` (`running`/`triggered`/`triggerFailed`), `worktreePath`, `baseBranch`, `baseRef`, `codexThreadID`, `codexThreadURL`, `errorMessage`, `createdAt`, `completedAt` (nullable fields are JSON `null`)

## Common mistakes

- Parsing human output instead of `--json`.
- Killing `task send` because it "hangs" — it is waiting for Codex; that's
  the contract.
- Retrying a `lifecycleViolation` (exit 3) — it will never succeed; the
  rule is the point.
- Touching `~/Library/Application Support/Operator/operator.sqlite`
  directly — schema and invariants are not a public API.
