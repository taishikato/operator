# Plan 010: Ship canonical operator CLI and agent support

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report. When done, update the status row for this plan in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat c4ec8d4..HEAD -- cursor_operator/Sources/CursorOperatorCLI cursor_operator/Sources/CursorOperatorCLICore cursor_operator/script/install_cli.sh cursor_operator/script/install_skills.sh cursor_operator/skills codex_operator/Sources/OperatorCLICore codex_operator/script/install_cli.sh codex_operator/script/install_skills.sh`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MED
- **Depends on**: plans/007-cursor-harness-on-operator-model.md, plans/009-codex-app-server-harness.md
- **Category**: dx
- **Planned at**: commit `c4ec8d4`, 2026-06-27

## Why this matters

Operator is intended to be agent-drivable.
The canonical command must become `operator`, not `cursor-operator`, and it must understand both Cursor and Codex harnesses.
This plan integrates the existing Cursor CLI surface with the Codex Operator CLI safety lessons, especially that Codex CLI sends must wait for the initial turn because the CLI owns the spawned app-server.

## Current state

- Cursor Operator package exposes `cursor-operator-cli`.
- Cursor CLI JSON DTOs already include task `harness`, but the command names and error text still say Cursor.
- Cursor install script symlinks `cursor-operator`.
- Codex Operator has an `operator-cli` product and an `operator` install flow.
- Codex CLI send waits for turn completion.

Important excerpts:

```swift
// cursor_operator/Sources/CursorOperatorCLICore/CursorOperatorCLICommands.swift:26
public struct CursorCLITask: Codable, Equatable, Sendable {
    public let id: String
    public let repositoryID: String
    public let title: String
    public let prompt: String
    public let autoCreatePR: Bool
    public let reasoningEffort: String
    public let useFastModel: Bool
    public let harness: String
```

```swift
// cursor_operator/Sources/CursorOperatorCLICore/CursorOperatorCLICommands.swift:126
"No Cursor repository named or identified by '\(reference)'. Run `cursor-operator repo list`."
```

```bash
# cursor_operator/script/install_cli.sh:1
# Builds the Cursor Operator CLI in release mode and symlinks it into
# ~/.local/bin as `cursor-operator`.
```

```swift
// codex_operator/Sources/OperatorCLICore/OperatorCLICommands.swift:189
/// Triggers Codex for a ready task and blocks until the turn completes.
/// The spawned app-server dies with this process, so returning before
/// completion would abort the turn — there is deliberately no fire-and-
/// forget variant (PRD decision 4).
```

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| CLI core tests | `cd cursor_operator && swift test --filter CursorOperatorCLICoreTests` | exit 0 |
| CLI integration tests | `cd cursor_operator && swift test --filter CursorOperatorCLIIntegrationTests` | exit 0 |
| Build release CLI | `cd cursor_operator && swift build -c release --product operator-cli` | exit 0 |
| Full tests | `cd cursor_operator && swift test` | exit 0 |

If target names change as part of the rebrand, run the equivalent renamed test targets and the full `swift test`.

## Scope

**In scope:**

- Canonical `operator` CLI command.
- CLI JSON DTOs for repositories, tasks, and runs.
- Harness-aware `task send`.
- Codex wait-required CLI behavior.
- Cursor existing wait behavior.
- Install CLI script.
- Install Skills script.
- Operator skill text.
- Settings agent support status/actions if not already covered by earlier plans.

**Out of scope:**

- `cursor-operator` compatibility alias.
- GitHub issue publishing.
- Direct SQLite manipulation from skills.
- CLI daemon/background no-wait Codex sends.
- Additional harnesses beyond Cursor and Codex.

## Git workflow

- Branch: `codex/operator-cli-agent-support`
- Commit message example: `feat: add operator cli agent support`
- Do not push unless instructed.

## Steps

### Step 1: Rename CLI product and installed command

Rename the user-facing CLI to `operator`.
Use internal product name `operator-cli` if needed to avoid app product collisions.
Update install script to symlink `operator`.
Do not install `cursor-operator`.

**Verify**: `cd cursor_operator && swift build -c release --product operator-cli` -> exit 0.

### Step 2: Make CLI DTOs harness-aware

Task JSON must include harness.
Run JSON must include harness and provider-specific nullable artifact fields for Cursor and Codex.
Nil optionals should encode as JSON null where existing agent contracts expect stable key sets.

**Verify**: `cd cursor_operator && swift test --filter CursorOperatorCLICoreTests` -> exit 0.

### Step 3: Route `task send` by task harness

If the task harness is Cursor, use Cursor send behavior and optional Cursor wait behavior.
If the task harness is Codex, use Codex trigger and wait for initial turn completion.
Return distinct lifecycle and provider errors.
Do not offer no-wait Codex send.

**Verify**: add fake Cursor and fake Codex send tests, then run `cd cursor_operator && swift test --filter CursorOperatorCLICoreTests` -> exit 0.

### Step 4: Update CLI binary integration tests

Update binary tests to use `operator`.
Verify JSON envelopes, usage errors, lifecycle errors, and task/run schemas.

**Verify**: `cd cursor_operator && swift test --filter CursorOperatorCLIIntegrationTests` -> exit 0.

### Step 5: Install and document agent skill

Update or create the Operator skill source so it documents:

- `operator repo list`
- `operator repo add`
- `operator task add`
- `operator task list`
- `operator task send`
- `operator run list`
- Cursor and Codex source differences
- Codex wait-required behavior

The skill must be thin and must not include SQL, database paths, secrets, or lifecycle logic.

**Verify**: `cd cursor_operator && ./script/install_skills.sh` should work in a disposable HOME during tests, or add tests that exercise the installer against temporary directories.

## Test plan

- CLI command tests for repository list/add.
- CLI command tests for task add/list/show/archive.
- CLI command tests for harness-aware send.
- CLI tests for Codex wait behavior using a fake completion signal.
- CLI tests for Cursor wait behavior using fake runtime.
- Integration tests for JSON key sets and exit codes.
- Installer tests using temporary HOME or injectable destinations.

## Done criteria

- [ ] `cd cursor_operator && swift build -c release --product operator-cli` exits 0.
- [ ] `cd cursor_operator && swift test` exits 0.
- [ ] `operator` is the installed command.
- [ ] No `cursor-operator` compatibility alias is added.
- [ ] CLI task JSON includes harness.
- [ ] CLI run JSON includes harness and provider artifacts.
- [ ] Codex CLI send waits for initial turn completion.
- [ ] Cursor CLI send preserves existing behavior.
- [ ] Operator skill documents Cursor and Codex source differences.
- [ ] `plans/README.md` status row for plan 010 is updated.

## STOP conditions

Stop and report if:

- Product naming collisions cannot be resolved with `operator-cli`.
- Codex CLI send cannot wait without changing Codex trigger ownership semantics.
- The skill would need direct DB access to satisfy any story.
- Installer tests require touching the real user's home directory.

## Maintenance notes

Agent-facing contracts are sticky.
Review JSON schema changes carefully and prefer adding fields over changing existing field meanings.
The Codex no-wait prohibition is intentional; do not relax it without a new design decision.
