# Plan 007: Port Cursor harness behavior onto Operator Task and Run

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report. When done, update the status row for this plan in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat c4ec8d4..HEAD -- cursor_operator/Sources/CursorOperatorCore/Runtime cursor_operator/Sources/CursorOperatorCore/Credentials cursor_operator/Sources/CursorOperatorCore/Models cursor_operator/Sources/CursorOperatorCore/Views cursor_operator/Tests/CursorOperatorCoreTests`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: plans/006-unified-task-run-model.md
- **Category**: migration
- **Planned at**: commit `c4ec8d4`, 2026-06-27

## Why this matters

After the model changes, Cursor must still work exactly as it does today.
This plan moves the existing Cursor Cloud Agent send and monitor path onto the unified Operator Task/Run model without adding Codex behavior.
It is the regression shield before Codex integration starts.

## Current state

- `CursorTaskSendService` starts Cursor Cloud Agent through `CursorCloudAgentRuntime`.
- It creates a pending attempt before contacting Cursor, records success with Cursor agent/run/URL, and records sanitized failure.
- `CursorRuntimeFailure` sanitizes noisy or secret-bearing errors.
- `CursorSendPreview` already carries repository URL, starting ref, fixed model, auto-create PR, prompt, reasoning effort, fast model, and harness.

Important excerpts:

```swift
// cursor_operator/Sources/CursorOperatorCore/Runtime/CursorTaskSendService.swift:106
public func send(taskID: UUID) async throws -> CursorRunAttempt {
    let apiKey = try credentialReadiness.apiKeyForSending()
    guard let task = try store.task(id: taskID),
          let repository = try store.repository(id: task.repositoryID) else {
        throw CursorOperatorStoreError.taskNotFound
    }
```

```swift
// cursor_operator/Sources/CursorOperatorCore/Runtime/CursorTaskSendService.swift:117
let preview = try CursorSendPreview(task: task, repository: repository)
let request = CursorCloudAgentRequestPreview(
    agentName: preview.agentName,
    prompt: preview.prompt,
    repositoryURL: preview.repositoryURL,
    startingRef: preview.startingRef,
    model: preview.model,
    autoCreatePR: preview.autoCreatePR
)
```

```swift
// cursor_operator/Sources/CursorOperatorCore/Runtime/CursorTaskSendService.swift:156
} catch let failure as CursorRuntimeFailure {
    return try store.recordFailedClaimedSendAttempt(
        id: pendingAttempt.id,
        errorMessage: failure.message
    )
}
```

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Cursor send tests | `cd cursor_operator && swift test --filter CursorTaskSendServiceTests` | exit 0 |
| Cursor monitor tests | `cd cursor_operator && swift test --filter CursorRunMonitorServiceTests` | exit 0 |
| Board tests | `cd cursor_operator && swift test --filter CursorBoardModelTests` | exit 0 |
| Full tests | `cd cursor_operator && swift test` | exit 0 |

## Scope

**In scope:**

- Cursor send service.
- Cursor monitor service.
- Cursor readiness and credential flow only as needed to keep current behavior.
- Cursor send preview.
- Board/card/inspector projections for Cursor-specific artifacts.
- Tests around prompt verbatim, Cursor URL, auto-create PR, and failure status.

**Out of scope:**

- Codex settings or runtime.
- CLI rework.
- Replacing the Cursor SDK helper.
- Adding Cursor Desktop deep links.
- Changing the PRD's fixed Cursor model.

## Git workflow

- Branch: `codex/cursor-harness-operator-model`
- Commit message example: `refactor: port cursor harness to operator runs`
- Do not push unless instructed.

## Steps

### Step 1: Adapt Cursor send service to create Operator Runs

Change the Cursor send path to use the neutral Run creation APIs from plan 006.
The Run must have harness `cursor`, prompt snapshot, repository URL, starting ref, model `composer-2.5`, `autoCreatePR`, Cursor agent ID, Cursor run ID, Cursor URL, and sanitized error.

Do not change the Cursor SDK helper protocol unless the new Run API requires a DTO rename.

**Verify**: `cd cursor_operator && swift test --filter CursorTaskSendServiceTests` -> exit 0.

### Step 2: Adapt Cursor monitor to update Operator Runs and Task state

Update monitoring/resume code so a completed Cursor run moves the Task to Done and a terminal unsuccessful run moves it to Failed.
Preserve the existing SDK wait-based behavior.

**Verify**: `cd cursor_operator && swift test --filter CursorRunMonitorServiceTests` -> exit 0.

### Step 3: Preserve Cursor source semantics in preview and UI

Ensure Cursor send preview shows that Cursor starts from the GitHub remote/default branch and excludes local dirty changes.
Cards and detail should show Cursor harness badge and Open in Cursor action from the Run artifact.

**Verify**: `cd cursor_operator && swift test --filter CursorTaskCreationAndPreviewTests` -> exit 0.

### Step 4: Verify current Cursor user flows still work

Run full tests and update any renamed assertions from Cursor-specific DTOs to Operator DTOs.

**Verify**: `cd cursor_operator && swift test` -> exit 0.

## Test plan

- Existing Cursor send service tests should still cover successful send, failed send, prompt verbatim, model, repository URL, starting ref, auto-create PR, and sanitized errors.
- Add tests that Cursor failure moves Task to Failed when the provider has accepted/started execution and monitoring terminally fails.
- Add tests that failed retry creates a second Run on the same Task.
- Keep credential tests isolated from the real Keychain.

## Done criteria

- [ ] `cd cursor_operator && swift test` exits 0.
- [ ] Cursor successful send records an Operator Run with harness `cursor`.
- [ ] Cursor failed send records sanitized error on the Run.
- [ ] Cursor completion moves Task to Done.
- [ ] Cursor terminal failure moves Task to Failed.
- [ ] Cursor Open action uses saved Cursor URL.
- [ ] Prompt text is still sent exactly as written.
- [ ] `plans/README.md` status row for plan 007 is updated.

## STOP conditions

Stop and report if:

- Cursor SDK helper request shape must change in a provider-breaking way.
- The new Run model cannot represent Cursor `agentID`, `runID`, and `openURL`.
- Tests require storing raw Cursor API keys outside Keychain/test fakes.
- Cursor completion semantics conflict with the PRD's Done definition.

## Maintenance notes

This plan should be reviewed as a compatibility preservation change.
The biggest risk is accidentally changing existing Cursor behavior while doing neutral naming work.
Keep provider-specific names in Cursor runtime code where they clarify Cursor-only behavior.
