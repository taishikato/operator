# Codex Operator 🪄

Codex Operator (`codex_operator`) is a desktop app for Codex App.

It gives you a local Kanban board for coding tasks. When a task is ready, Codex Operator prepares a detached Git worktree, sends the prompt directly to Codex, and opens the resulting chat session in Codex App so you can continue working there.

![Codex Operator](https://github.com/user-attachments/assets/44917bdf-6960-4bd6-a4d5-d81bed7412c3)

## What It Does

- Manage coding tasks on a local Kanban board.
- Register local Git repositories and choose their default branch.
- Create tasks with a title, prompt, repository, and reasoning effort.
- Trigger Codex directly from a task.
- Create isolated worktrees for Codex runs under `~/.codex/worktrees`.
- Open finished Codex sessions in Codex App.
- Keep task and run metadata in a local SQLite database.

## Run Locally

From this directory:

```bash
script/build_and_run.sh
```

This stops any running `Operator` process, rebuilds the app bundle, and opens
`dist/Operator.app`.

Other useful script modes:

```bash
script/build_and_run.sh --bundle
script/build_and_run.sh --verify
script/build_and_run.sh --logs
script/build_and_run.sh --telemetry
script/build_and_run.sh --debug
```

A downloadable `.dmg` build is planned for the near future.

## Operator CLI and agent skills

Coding agents (Claude Code, Codex) can drive the board through a
first-class `operator` CLI instead of the UI:

```bash
script/install_cli.sh     # builds release and symlinks ~/.local/bin/operator
script/install_skills.sh  # links the agent skill into ~/.claude/skills and ~/.codex/skills
```

`operator --help` shows the verb surface (`repo list`,
`task add/list/show/archive/send`, `run list`). Every verb accepts `--json`
with a stable schema and distinct exit codes, so agents can branch on
"task not found" vs "the lifecycle forbids this". `task send` stays alive
until the Codex turn completes — exiting early aborts the turn. The CLI
shares the app's domain library and database (WAL mode), and a running app
picks up CLI writes within a couple of seconds.

For development and testing the CLI can be sandboxed away from the real
board: `OPERATOR_DB=/path/operator.sqlite` overrides the database, and
`OPERATOR_DATA_DIR=/path` relocates the directories `task send` writes to
(app data and the worktree root). Set both together — with only
`OPERATOR_DB`, a send would still run git operations against the
production worktree root.

Design decisions live in `.scratch/operator-skills/PRD.md`; the skill
itself is `skills/operator/SKILL.md`.

## Requirements

Codex Operator requires:

- macOS 26.0 or newer.
- Git.
- Codex App and Codex CLI installed and signed in.

Codex Operator checks Codex availability with:

```bash
codex login status
```

It sends tasks through the Codex app server:

```bash
codex app-server --listen stdio://
```

If Codex is not found automatically, open Settings in Codex Operator and configure the absolute path to the `codex` binary.

## Basic Workflow

1. Open Codex Operator.
2. Click **Add Repository** and choose a local Git repository.
3. Confirm or edit the repository default branch in Settings.
4. Click **New Ticket**.
5. Choose the repository, enter a task title, write the Codex prompt, and select a reasoning effort.
6. Send the task to Codex from the card or inspector.
7. Codex Operator creates a detached worktree from the repository default branch.
8. Codex starts a chat session for the task.
9. When the initial turn completes, open the session in Codex App and continue working there.

## Board Columns

- **Ready**: editable tasks that can be sent to Codex.
- **Running**: tasks that have been sent to Codex and are waiting for the initial turn to finish.
- **Done**: tasks whose initial Codex turn has finished. These can be opened in Codex App.
- **Archived**: hidden tasks available from the Archived view.

## Local Data

Codex Operator stores its SQLite database in:

```text
~/Library/Application Support/Operator/operator.sqlite
```

Codex worktrees are created under:

```text
~/.codex/worktrees
```

The app stores task metadata, repository paths, run state, worktree paths, and Codex thread references. It does not store Codex credentials.

## Development

Run tests:

```bash
swift test
```

Build:

```bash
swift build
```

The Swift package exposes:

- `OperatorDesktop`: the main library target.
- `Operator`: the executable app target.
- `OperatorDesktopTests`: the test target.

## Notes

- Codex Operator currently uses the fixed Codex model configured in the app code.
- A task can only be sent to Codex once after a successful trigger.
- Failed triggers stay on the board with a failure badge so you can inspect what happened.
- The app is local-first and expects repositories to already exist on your machine.
