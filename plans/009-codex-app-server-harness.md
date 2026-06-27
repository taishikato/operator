# Plan 009: Implement Codex app-server harness in Operator

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report. When done, update the status row for this plan in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat c4ec8d4..HEAD -- cursor_operator/Sources/CursorOperatorCore codex_operator/Sources/OperatorDesktop/Repositories codex_operator/Tests/OperatorDesktopTests/CodexTriggerServiceTests.swift docs/codex-app-worktree-discovery.md docs/codex-thread-visibility-discovery.md`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding.

## Status

- **Priority**: P1
- **Effort**: L
- **Risk**: HIGH
- **Depends on**: plans/006-unified-task-run-model.md, plans/008-codex-readiness-and-configuration.md
- **Category**: migration
- **Planned at**: commit `c4ec8d4`, 2026-06-27

## Why this matters

This is the core Codex integration.
The user specifically wants to use Codex Operator code to add Codex support into Operator.
This plan ports the proven Codex worktree, app-server, thread visibility, recovery, and Open in Codex behavior onto the new Operator Task/Run model.

## Current state

Codex Operator already has the necessary deep modules:

- `WorktreePreparer` creates detached worktrees and has Codex-compatible path logic.
- `CodexTriggerService` starts a Codex thread/turn, records a run, hides thread while running, and completes the run when the turn finishes.
- `CodexCLIThreadVisibilityController` hides and reveals threads using external `codex archive` and `codex unarchive`.
- Codex app-server client and tests exist in `codex_operator`.

Important excerpts:

```swift
// codex_operator/Sources/OperatorDesktop/Repositories/WorktreePreparer.swift:49
public func prepareWorktree(for repository: OperatorRepository) throws -> PreparedWorktree {
    let repositoryURL = URL(filePath: repository.path).standardizedFileURL
    let baseBranch = repository.defaultBranch
    let baseRef = try resolveBaseRef(repositoryURL: repositoryURL, branch: baseBranch)
    let gitOriginURL = resolveGitOriginURL(repositoryURL: repositoryURL)
    let worktreeURL = codexCompatibleWorktreeURL(...)
```

```swift
// codex_operator/Sources/OperatorDesktop/Repositories/CodexTriggerService.swift:129
public struct CodexTriggerService: @unchecked Sendable {
    public static let fixedModel = "gpt-5.5"
```

```swift
// codex_operator/Sources/OperatorDesktop/Repositories/CodexTriggerService.swift:179
let startedThread = try await appServerClient.startThreadAndTurn(
    CodexThreadStartRequest(
        cwd: preparedWorktree.worktreeURL,
        gitInfo: preparedWorktree.gitOriginURL.map { ... },
        model: Self.fixedModel,
        reasoningEffort: task.reasoningEffort,
        prompt: task.prompt,
        displayName: task.title
    )
)
```

```swift
// codex_operator/Sources/OperatorDesktop/Repositories/CodexThreadVisibilityController.swift:58
public func hideThread(id: String) async -> Bool {
    guard let binaryURL = effectiveBinaryURL() else {
        return false
    }
    ...
    if await Self.runCodex(binaryURL: binaryURL, arguments: ["archive", id]) {
        return true
    }
}
```

Docs that constrain behavior:

- `docs/codex-app-worktree-discovery.md`
- `docs/codex-thread-visibility-discovery.md`

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Codex send tests | `cd cursor_operator && swift test --filter CodexTriggerServiceTests` | exit 0 |
| Worktree tests | `cd cursor_operator && swift test --filter WorktreePreparerTests` | exit 0 |
| App-server tests | `cd cursor_operator && swift test --filter CodexAppServerStdioClientTests` | exit 0 |
| Full tests | `cd cursor_operator && swift test` | exit 0 |

If the test target names differ after porting, use `cd cursor_operator && swift test` as the verification gate.

## Scope

**In scope:**

- Codex worktree preparer.
- Codex app-server stdio client.
- Codex trigger service.
- Codex thread visibility controller.
- Codex process environment helper.
- Codex open target/opener.
- Codex interrupted-run recovery.
- Tests ported from Codex Operator and adapted to Operator Task/Run.

**Out of scope:**

- Cursor behavior changes.
- CLI behavior.
- Model selection.
- Prompt augmentation.
- Codex-only repositories without GitHub origin.
- Automatic worktree cleanup.

## Git workflow

- Branch: `codex/codex-app-server-harness`
- Commit message example: `feat: add codex app-server harness`
- Do not push unless instructed.

## Steps

### Step 1: Port Codex support modules with minimal semantic changes

Copy/adapt Codex support modules from Codex Operator into the Operator core.
Keep `Codex` prefixes for Codex-specific modules.
Adapt repository/task/run types to the new Operator model from plan 006.

**Verify**: `cd cursor_operator && swift build` -> exit 0.

### Step 2: Configure Codex worktree root

Production Codex worktree root must be `~/.codex/worktrees`.
Tests may inject a temporary worktree root.
The path shape must be `<short-id>/<repo-name>`.

**Verify**: `cd cursor_operator && swift test --filter WorktreePreparerTests` -> exit 0.

### Step 3: Start Codex thread and turn from the worktree

The request must use fixed model `gpt-5.5`, selected reasoning effort, and prompt exactly as written.
Both `thread/start.cwd` and `turn/start.cwd` must be the prepared worktree.
Send Git metadata when available.
Do not add hidden prompt instructions.

**Verify**: `cd cursor_operator && swift test --filter CodexTriggerServiceTests` -> exit 0.

### Step 4: Record Codex Runs and Task state

On accepted thread/turn start, record a Run with harness `codex`, worktree path, base branch, base ref, thread ID, and thread URL.
Move Task to Running.
When initial turn completion watcher fires, reveal thread if needed, complete Run, and move Task to Done.
On provider or monitoring failure, move Task to Failed and store a short sanitized error.

**Verify**: `cd cursor_operator && swift test --filter CodexTriggerServiceTests` -> exit 0.

### Step 5: Port thread visibility and recovery behavior

Hide in-flight threads with external `codex archive`.
Reveal before Done with external `codex unarchive`.
Treat hide/reveal as best-effort.
Port interrupted-run recovery behavior as appropriate for app-owned runs.

**Verify**: `cd cursor_operator && swift test --filter CodexThreadVisibilityControllerTests` -> exit 0, or full `swift test` if test names differ.

### Step 6: Port Open in Codex App behavior

Add provider artifacts and actions so Codex Run detail can open the thread URL first and fall back to worktree path.

**Verify**: `cd cursor_operator && swift test --filter CodexOpenTargetTests` -> exit 0, or full `swift test`.

## Test plan

- Port Codex Operator tests for trigger service, app-server client, worktree preparer, visibility controller, open target, status, and process environment.
- Adapt tests to the Operator Task/Run model and Ready/Running/Failed/Done states.
- Use fake app-server clients and fake command runners.
- Do not require real Codex installation in unit tests.
- Keep manual regression checks documented for real Codex App behavior.

## Done criteria

- [ ] `cd cursor_operator && swift build` exits 0.
- [ ] `cd cursor_operator && swift test` exits 0.
- [ ] Codex successful send records a Run with harness `codex`.
- [ ] Codex prompt is sent exactly as written.
- [ ] Codex fixed model is `gpt-5.5`.
- [ ] Codex worktree path uses `~/.codex/worktrees/<short-id>/<repo-name>` in production configuration.
- [ ] Thread and turn cwd both point at the worktree.
- [ ] Hide failure does not fail the Run.
- [ ] Reveal occurs before Done when hide succeeded.
- [ ] Open in Codex App prefers thread URL and falls back to worktree path.
- [ ] `plans/README.md` status row for plan 009 is updated.

## STOP conditions

Stop and report if:

- Current Codex CLI/app-server APIs no longer match the existing Codex Operator implementation.
- The integrated Run model cannot represent Codex thread ID, URL, worktree path, base branch, and base ref.
- You need to inspect diffs, parse transcripts, or classify Codex output to complete the plan.
- Real Codex credentials would be needed for unit tests.

## Maintenance notes

This plan depends on observed Codex App behavior.
Reviewers should compare any worktree or visibility changes against `docs/codex-app-worktree-discovery.md` and `docs/codex-thread-visibility-discovery.md`.
Do not "simplify" by starting the thread in the source checkout; that breaks takeover isolation.
