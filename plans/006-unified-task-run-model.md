# Plan 006: Introduce unified Task and Run model with Failed retry

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report. When done, update the status row for this plan in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat c4ec8d4..HEAD -- cursor_operator/Sources/CursorOperatorCore/Models cursor_operator/Sources/CursorOperatorCore/Persistence cursor_operator/Tests/CursorOperatorCoreTests`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding.

## Status

- **Priority**: P1
- **Effort**: L
- **Risk**: HIGH
- **Depends on**: plans/005-operator-rebrand-foundation.md
- **Category**: migration
- **Planned at**: commit `c4ec8d4`, 2026-06-27

## Why this matters

The PRD requires a Task to be the user-facing card and a Run to be one provider execution attempt.
The current Cursor model already has task harness fields, but run records are still Cursor-specific `runAttempts`.
This plan creates the neutral data foundation needed for Codex integration, Failed retry, Run history, and later harness expansion.

## Current state

- `CursorTask` already stores `harness`, `reasoningEffort`, and `useFastModel`.
- `CursorRunAttempt` is Cursor-specific and stores Cursor Cloud Agent metadata.
- The database table is still named `runAttempts`.
- There are partial unique indexes that prevent multiple pending/succeeded attempts per task.
- Failed send currently leaves the task Ready in lifecycle policy, but the PRD wants terminal provider failures to move the task to Failed and allow explicit recovery to Ready.

Important excerpts:

```swift
// cursor_operator/Sources/CursorOperatorCore/Models/CursorTaskLifecycle.swift:19
public enum CursorTaskStatus: String, Codable, CaseIterable, Sendable {
    case ready
    case running
    case failed
    case done
    case archived
}
```

```swift
// cursor_operator/Sources/CursorOperatorCore/Models/CursorTaskLifecycle.swift:96
public static func recordFailedSend(for task: CursorTask) throws -> CursorTask {
    guard task.status == .ready else {
        throw CursorTaskLifecycleError.transitionNotAllowed
    }

    return task
}
```

```swift
// cursor_operator/Sources/CursorOperatorCore/Persistence/CursorOperatorStore.swift:20
public struct CursorRunAttempt: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let taskID: UUID
    public let repositoryID: UUID
    public let status: CursorRunAttemptStatus
    public let repositoryURL: URL
    public let startingRef: String
    public let model: String
    public let autoCreatePR: Bool
    public let prompt: String
    public let cursorAgentID: String?
    public let cursorRunID: String?
    public let cursorURL: URL?
    public let errorMessage: String?
    public let createdAt: Date
    public let completedAt: Date
}
```

```swift
// cursor_operator/Sources/CursorOperatorCore/Persistence/CursorOperatorStore.swift:687
try db.create(table: "runAttempts") { table in
    table.column("id", .text).primaryKey()
    table.column("taskID", .text).notNull().references("tasks", onDelete: .restrict)
    table.column("repositoryID", .text).notNull().references("repositories", onDelete: .restrict)
    table.column("status", .text).notNull()
    ...
}
```

Repo conventions:

- Store code uses GRDB, explicit SQL, migrations, and typed mapping helpers.
- Store tests live in `CursorStoreTests`.
- Lifecycle tests live in `CursorTaskLifecyclePolicyTests`.
- Projection/model tests live in `CursorBoardModelTests`.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Tests | `cd cursor_operator && swift test --filter CursorTaskLifecyclePolicyTests` | exit 0 |
| Store tests | `cd cursor_operator && swift test --filter CursorStoreTests` | exit 0 |
| Full package tests | `cd cursor_operator && swift test` | exit 0 |
| Build | `cd cursor_operator && swift build` | exit 0 |

## Scope

**In scope:**

- Shared task lifecycle types.
- Store entities and migrations for Tasks and Runs.
- Board projection support for latest/current Run and Run history.
- Tests for lifecycle, persistence, and projection.

**Out of scope:**

- Cursor SDK request behavior.
- Codex app-server behavior.
- CLI product renaming.
- User-facing design polish beyond whatever is needed to expose Run history minimally.
- Data migration from old real user databases.

## Git workflow

- Branch: `codex/unified-task-run-model`
- Commit message example: `feat: add unified task run model`
- Do not push unless instructed.

## Steps

### Step 1: Rename shared domain types away from Cursor-specific names

Introduce neutral names for shared domain concepts, such as `OperatorTask`, `OperatorTaskStatus`, `OperatorHarness`, `OperatorRun`, and `OperatorRunStatus`.
Keep Cursor-specific names for Cursor runtime and credentials.
Use typealiases temporarily only if they reduce churn and are removed by the end of the plan.

**Verify**: `cd cursor_operator && swift build` -> exit 0.

### Step 2: Replace Cursor run attempts with harness-aware Runs

Add a neutral Run model that can store:

- task ID and repository ID
- harness
- status
- prompt snapshot
- harness settings snapshot or explicit provider settings fields
- Cursor provider IDs and URL
- Codex provider fields reserved for later plans
- error message
- timestamps

The first implementation can keep nullable provider-specific columns rather than inventing a JSON metadata blob.
Use migrations; do not rely on deleting real user data.
Since the new Operator app data path starts fresh, migration complexity can stay simple, but tests should still cover new schema creation.

**Verify**: `cd cursor_operator && swift test --filter CursorStoreTests` -> exit 0.

### Step 3: Implement Failed retry lifecycle

Add explicit lifecycle support:

```text
Ready --send accepted--> Running
Running --provider boundary completed--> Done
Running --provider or monitoring failure--> Failed
Failed --recover for retry--> Ready
Ready/Running/Failed/Done --archive--> Archived
```

Done must not become Ready.
Archived must not become Ready.
Retry must keep the same Task ID.

**Verify**: `cd cursor_operator && swift test --filter CursorTaskLifecyclePolicyTests` -> exit 0.

### Step 4: Add Run history projections

Update board/task detail models so cards can show the latest/current Run and task detail can list compact Run history.
The initial UI can be minimal, but tests must prove historical failed Runs remain after retry.

**Verify**: `cd cursor_operator && swift test --filter CursorBoardModelTests` -> exit 0.

### Step 5: Keep prompt and settings snapshots immutable

When a send creates a Run, store the prompt and harness settings on the Run.
Changing a Failed task before retry must not mutate prior Run snapshots.

**Verify**: `cd cursor_operator && swift test --filter CursorStoreTests` -> exit 0 and includes a test for failed retry preserving old snapshot.

## Test plan

- Add lifecycle tests for Failed -> Ready and Done -> Ready rejection.
- Add persistence tests for one Task with two Runs after a failed retry.
- Add persistence tests for prompt/settings snapshots on each Run.
- Add projection tests that a card shows latest/current Run while detail exposes history.
- Use existing store and lifecycle tests as patterns.

## Done criteria

- [ ] `cd cursor_operator && swift build` exits 0.
- [ ] `cd cursor_operator && swift test` exits 0.
- [ ] A Task can have multiple Run records.
- [ ] Retry creates a new Run on the same Task, not a new Task.
- [ ] Done tasks cannot be retried.
- [ ] Previous failed Run prompt/settings snapshots remain unchanged after retry.
- [ ] `plans/README.md` status row for plan 006 is updated.

## STOP conditions

Stop and report if:

- The change requires migrating real old Cursor Operator or Codex Operator data.
- The schema design needs a broad JSON metadata strategy instead of explicit fields.
- The UI requires a large redesign before store/lifecycle behavior can be verified.
- You cannot preserve existing Cursor send behavior in tests after introducing Runs.

## Maintenance notes

This is the highest-risk foundation plan.
Reviewers should focus on lifecycle transitions, partial unique indexes, and whether provider-specific fields are clear enough for both Cursor and Codex.
Do not let UI naming cleanup hide data model regressions.
