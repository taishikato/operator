# Plan 008: Add Codex readiness and task configuration to Operator

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report. When done, update the status row for this plan in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat c4ec8d4..HEAD -- cursor_operator/Sources/CursorOperatorCore/Models cursor_operator/Sources/CursorOperatorCore/Views cursor_operator/Sources/CursorOperatorCore/Runtime cursor_operator/Sources/CursorOperatorCore/Repositories codex_operator/Sources/OperatorDesktop/Repositories/CodexBinarySettings.swift codex_operator/Sources/OperatorDesktop/Repositories/CodexStatusChecker.swift`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: plans/005-operator-rebrand-foundation.md, plans/006-unified-task-run-model.md
- **Category**: migration
- **Planned at**: commit `c4ec8d4`, 2026-06-27

## Why this matters

Codex should become visible and configurable before it can send tasks.
This plan adds the Settings, readiness, and task-form parts of Codex without touching app-server execution.
That gives the UI and data model a narrow, testable path for selecting Codex and seeing whether it is available.

## Current state

- Cursor tasks already have a `harness` field and a three-value `CursorReasoningEffort`.
- Codex Operator has binary settings and status checks that should be transplanted.
- Codex Operator uses `ReasoningEffort` with `low`, `medium`, `high`, and `xhigh`.
- Cursor Operator settings currently focus on Cursor credentials, Node, repository setup, and agent support.

Important excerpts:

```swift
// cursor_operator/Sources/CursorOperatorCore/Models/CursorTaskLifecycle.swift:7
public enum CursorHarness: String, Codable, CaseIterable, Sendable {
    case cursor
    case codex
    case claudeCode = "claude-code"
}
```

```swift
// cursor_operator/Sources/CursorOperatorCore/Models/CursorTaskLifecycle.swift:13
public enum CursorReasoningEffort: String, Codable, CaseIterable, Sendable {
    case low
    case medium
    case high
}
```

```swift
// codex_operator/Sources/OperatorDesktop/Models/TaskLifecycle.swift:3
public enum ReasoningEffort: String, Codable, CaseIterable, Sendable {
    case low
    case medium
    case high
    case xhigh
}
```

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Settings tests | `cd cursor_operator && swift test --filter CursorCredentialSettingsTests` | exit 0 |
| Creation tests | `cd cursor_operator && swift test --filter CursorTaskCreationAndPreviewTests` | exit 0 |
| Shell/UI model tests | `cd cursor_operator && swift test --filter CursorOperatorShellSpecTests` | exit 0 |
| Full tests | `cd cursor_operator && swift test` | exit 0 |

## Scope

**In scope:**

- Codex binary settings provider/manager/detector transplanted into Cursor Operator core with Operator naming where shared.
- Codex status checker transplanted into Operator settings.
- Default Harness app setting.
- Codex reasoning effort including `xhigh`.
- Harness-specific task creation/editing fields.
- Tests for Codex readiness and default harness persistence.

**Out of scope:**

- Starting Codex app-server.
- Creating Codex worktrees.
- Hiding/revealing Codex threads.
- CLI send behavior.
- Collecting Codex credentials.

## Git workflow

- Branch: `codex/codex-readiness-configuration`
- Commit message example: `feat: add codex harness readiness`
- Do not push unless instructed.

## Steps

### Step 1: Add Codex-capable configuration types

Transplant Codex binary settings and status checker concepts from Codex Operator.
Use Operator naming for shared settings models, but keep `Codex` prefixes for Codex-specific types.
Codex binary override must require an absolute path.
Codex status should distinguish not checked, ready, not found, and unavailable/unauthenticated.

**Verify**: add focused tests for binary detection/override/status, then run `cd cursor_operator && swift test --filter CursorOperatorCoreTests` if the test target name supports it; otherwise run `cd cursor_operator && swift test`.

### Step 2: Add Default Harness setting

Persist a Default Harness setting with Cursor as the initial default.
Settings UI/model should allow choosing Cursor or Codex.
New task drafts should initialize with the Default Harness.

**Verify**: `cd cursor_operator && swift test --filter CursorCredentialSettingsTests` -> exit 0, with new tests for default harness persistence.

### Step 3: Add Codex task-form fields

Add Codex reasoning effort with `xhigh`.
When harness is Cursor, show Cursor fields such as auto-create PR and fixed model `composer-2.5`.
When harness is Codex, show reasoning effort and fixed model `gpt-5.5`.
Ready tasks can edit harness and relevant fields.

**Verify**: `cd cursor_operator && swift test --filter CursorTaskCreationAndPreviewTests` -> exit 0.

### Step 4: Add harness-specific readiness projection

Board and inspector projections should expose whether the selected harness is send-ready.
Cursor readiness comes from API key and Node.
Codex readiness comes from binary path and login/status.
Do not wire Codex send yet.

**Verify**: `cd cursor_operator && swift test` -> exit 0.

## Test plan

- Add tests for Codex binary override validation.
- Add tests for Codex status mapping.
- Add tests that Default Harness defaults to Cursor and can be changed to Codex.
- Add tests that a new task draft uses the stored Default Harness.
- Add tests that Codex task creation can store `xhigh`.
- Add tests that Cursor fields do not accidentally apply to Codex previews.

## Done criteria

- [ ] `cd cursor_operator && swift test` exits 0.
- [ ] Settings can persist Default Harness.
- [ ] Codex readiness can be displayed without starting Codex.
- [ ] Codex binary override rejects relative paths.
- [ ] Codex task configuration supports `xhigh`.
- [ ] No Codex credentials are collected or persisted.
- [ ] `plans/README.md` status row for plan 008 is updated.

## STOP conditions

Stop and report if:

- Codex status checking requires live network access.
- Codex CLI has changed enough that existing Codex Operator status logic no longer applies.
- Adding `xhigh` breaks existing Cursor task assumptions in a way that requires a broader settings redesign.
- You need to implement Codex app-server send to verify the settings path.

## Maintenance notes

This plan prepares the UI and settings for Codex but intentionally does not send.
Reviewers should check that Codex readiness does not prompt for or persist Codex credentials.
Keep the source distinction clear: Cursor is remote GitHub source, Codex is local default-branch worktree source.
