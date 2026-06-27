---
name: operator
description: Use when asked to file, list, inspect, archive, or send tasks on the user's Operator board, or when work surfaces a follow-up worth queueing for Cursor Cloud Agent.
---

# Operator board CLI

Operator is a local macOS Kanban board that prepares and sends tasks to Cursor Cloud Agent.
Drive it with the `operator` CLI only.
Do not read or write its SQLite database directly; the CLI uses the same CursorOperatorCore domain code as the app.

## Setup check

Run `operator --help`.
If the binary is missing, install it from the repo:

```bash
cursor_operator/script/install_cli.sh
cursor_operator/script/install_skills.sh
```

## Commands

Add `--json` to every command you parse; human output is not stable.

| Action | Command |
|--------|---------|
| List repositories | `operator repo list --json` |
| Register a repository | `operator repo add <path> --json` |
| Create a task | `operator task add --repo <name\|id> --title <t> --prompt <p> [--auto-create-pr] --json` |
| Create and send a task | `operator task add --repo <name\|id> --title <t> --prompt <p> [--auto-create-pr] --auto-send --json` |
| Multi-line prompt | `operator task add ... --prompt-file <path> --json` |
| List tasks | `operator task list [--repo <name\|id>] [--status ready\|running\|failed\|done\|archived] --json` |
| Show one task | `operator task show <task-id> --json` |
| Archive a task | `operator task archive <task-id> --json` |
| Send a Ready task to Cursor | `operator task send <task-id> [--wait] --json` |
| List a task's run attempts | `operator run list --task <task-id> --json` |

The prompt is sent to Cursor Cloud Agent verbatim, so write it as a complete, standalone instruction.
Resolve repository names via `repo list` first; ambiguous names require the id.

If the repository is not on the board yet, register it yourself with `repo add <path>`.
The path can be anywhere inside the Git working tree.
The CLI resolves the repository root, requires a GitHub origin remote, and infers the default branch.

## Storage

Operator stores data under Application Support `Operator`.
For tests or sandboxed agent work, set `CURSOR_OPERATOR_DB=/path/to/db.sqlite`.
Old Cursor Operator and Codex Operator local databases are not migrated.

## Lifecycle rules

- Statuses: `ready` -> `running` -> `done` or `failed`; `archived` removes a task from the active board.
- Only `ready` tasks can be sent.
- One successful Cursor send per task; do not retry lifecycle violations.
- Failed sends leave the task `ready`, so retry is allowed.
- `task send --wait` blocks until Cursor reports completion or failure.
- Archive is the only manual removal.
There is no hard delete.

## Exit codes and errors

| Exit | JSON `error.code` | Meaning / what to do |
|------|-------------------|----------------------|
| 0 | - | success |
| 2 | `notFound` | unknown repo/task id; re-check with `repo list` / `task list` |
| 3 | `lifecycleViolation` | the board forbids this; report it, do not retry |
| 4 | `cursorUnavailable` | Cursor API key is missing or unavailable |
| 5 | `sendFailed` | Cursor rejected or failed the run; inspect `run list` |
| 7 | `invalidRepository` | `repo add` path is not a usable GitHub repository |
| 8 | `alreadyRegistered` | repository path is already on the board |
| 64 | `usage` | bad arguments |
| 70 | `internal` | unexpected error |

With `--json`, errors print `{"error":{"code":"...","message":"..."}}` on stdout and still set the exit code.

## JSON shapes

- repository: `id`, `name`, `localPath`, `githubURL`, `defaultBranch`, `createdAt`, `updatedAt`
- task: `id`, `repositoryID`, `title`, `prompt`, `autoCreatePR`, `status`, `createdAt`, `updatedAt`
- task add auto-send result: `task`, `runAttempt`.
`runAttempt` is a run attempt object when `--auto-send` succeeds.
- run attempt: `id`, `taskID`, `repositoryID`, `status`, `repositoryURL`, `startingRef`, `model`, `autoCreatePR`, `prompt`, `cursorAgentID`, `cursorRunID`, `cursorURL`, `errorMessage`, `createdAt`, `completedAt`

## Common mistakes

- Parsing human output instead of `--json`.
- Touching the SQLite file directly.
- Retrying a `lifecycleViolation`; failed sends are retryable, lifecycle violations are not.
