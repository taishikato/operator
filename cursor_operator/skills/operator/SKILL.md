---
name: operator
description: Use when asked to file, list, inspect, archive, or send tasks on the user's Operator board.
---

# Operator board CLI

Operator is a local macOS board for creating tasks and sending them through Cursor or Codex.
Drive it with the `operator` CLI only.
Do not read or write Operator storage directly.

## Setup check

Run `operator --help`.
If the binary is missing, install it from the repo:

```bash
cursor_operator/script/install_cli.sh
cursor_operator/script/install_skills.sh
```

## Commands

Add `--json` to every command you parse.
Human output is not stable.

| Action | Command |
|--------|---------|
| List repositories | `operator repo list --json` |
| Register a repository | `operator repo add <path> --json` |
| Create a Cursor task | `operator task add --repo <name\|id> --title <t> --prompt <p> --harness cursor [--auto-create-pr] --json` |
| Create a Codex task | `operator task add --repo <name\|id> --title <t> --prompt <p> --harness codex --json` |
| Multi-line prompt | `operator task add --repo <name\|id> --title <t> --prompt-file <path> --harness cursor\|codex --json` |
| Create and send | `operator task add --repo <name\|id> --title <t> --prompt <p> --harness cursor\|codex --auto-send --json` |
| List tasks | `operator task list [--repo <name\|id>] [--status ready\|running\|failed\|done\|archived] --json` |
| Show one task | `operator task show <task-id> --json` |
| Archive a task | `operator task archive <task-id> --json` |
| Recover a failed task | `operator task recover <task-id> --json` |
| Send a Ready task | `operator task send <task-id> --json` |
| Send a Cursor task and wait | `operator task send <task-id> --wait --json` |
| List a task's runs | `operator run list --task <task-id> --json` |

The prompt is sent verbatim, so write it as a complete, standalone instruction.
Resolve repository names via `operator repo list --json` first.
Ambiguous names require the repository id.
If the repository is not on the board yet, register it yourself with `operator repo add <path> --json`.

## Harness behavior

Cursor tasks send the prompt to Cursor Cloud Agent.
Cursor starts from the registered GitHub remote and default branch.
Cursor does not include local dirty changes unless they have already been pushed to that source.
Use `--auto-create-pr` only for Cursor tasks.
Use `operator task send <task-id> --wait --json` when you need Cursor completion before continuing.

Codex tasks start from an Operator-prepared local worktree.
Codex uses the registered repository, default branch, selected reasoning effort, and the prompt exactly as written.
Codex sends always wait for the initial turn to complete because the CLI owns the spawned app-server.
There is no no-wait Codex send mode.

## Lifecycle rules

Statuses are `ready`, `running`, `done`, `failed`, and `archived`.
Only `ready` tasks can be sent.
Archive is the manual removal path.
Do not retry a `lifecycleViolation`.
For failed sends, inspect `operator run list --task <task-id> --json` before deciding what to do next.
When retry is appropriate, move the task back to `ready` with `operator task recover <task-id> --json`, then send again.

## Exit codes and errors

| Exit | JSON `error.code` | Meaning |
|------|-------------------|---------|
| 0 | - | success |
| 2 | `notFound` | unknown repo or task |
| 3 | `lifecycleViolation` | the board forbids this state change |
| 4 | `cursorUnavailable` | Cursor credentials are unavailable |
| 5 | `sendFailed` | provider send failed |
| 7 | `invalidRepository` | `repo add` path is not a usable GitHub repository |
| 8 | `alreadyRegistered` | repository path is already on the board |
| 64 | `usage` | bad arguments |
| 70 | `internal` | unexpected error |

With `--json`, errors print `{"error":{"code":"...","message":"..."}}` on stdout and still set the exit code.

## JSON shapes

- repository: `id`, `name`, `localPath`, `githubURL`, `defaultBranch`, `createdAt`, `updatedAt`
- task: `id`, `repositoryID`, `title`, `prompt`, `autoCreatePR`, `reasoningEffort`, `useFastModel`, `harness`, `status`, `createdAt`, `updatedAt`
- task add auto-send result: `task`, `runAttempt`
- run attempt: `id`, `taskID`, `repositoryID`, `status`, `repositoryURL`, `startingRef`, `model`, `autoCreatePR`, `prompt`, `harness`, `reasoningEffort`, `useFastModel`, `cursorAgentID`, `cursorRunID`, `cursorURL`, `worktreePath`, `baseBranch`, `baseRef`, `codexThreadID`, `codexThreadURL`, `errorMessage`, `createdAt`, `completedAt`

## Common mistakes

- Parsing human output instead of `--json`.
- Touching Operator storage directly.
- Assuming Codex has a no-wait send path.
- Using `--auto-create-pr` for Codex tasks.
