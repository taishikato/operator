# Cursor Auto Send Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.
> Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an optional auto-send capability so newly created Cursor Operator tasks can be sent to Cursor Cloud Agent immediately from both CLI and GUI creation paths.

**Architecture:** Keep task creation and task sending as separate domain capabilities, then add thin orchestration methods at the CLI command layer and board model layer.
The CLI returns the run attempt when `--auto-send` is requested, while normal `task add` behavior remains unchanged.
The GUI stores the choice on the draft and triggers the existing async send path only after a new task is created.

**Tech Stack:** Swift 6.2, Swift Testing, SwiftUI, ArgumentParser, GRDB.

---

## File Structure

- Modify `cursor_operator/Resources/CursorSDKHelper/cursor-sdk-helper.mjs` to make `sanitizeError` testable without resolving `@cursor/sdk` during import.
- Modify `cursor_operator/Tests/CursorOperatorCoreTests/CursorCloudAgentSDKRuntimeTests.swift` to assert the helper stderr when the process fails.
- Modify `cursor_operator/Sources/CursorOperatorCore/Models/CursorTaskCreation.swift` to add `autoSend` to `CursorTaskCreationDraft`.
- Modify `cursor_operator/Sources/CursorOperatorCore/Models/CursorBoardModel.swift` to create and optionally send a new task from the draft.
- Modify `cursor_operator/Sources/CursorOperatorCore/Views/CursorOperatorRootView.swift` to expose an `Auto-send` checkbox in the task sheet and route creation through the new model method.
- Modify `cursor_operator/Sources/CursorOperatorCLICore/CursorOperatorCLICommands.swift` to add an async `addTask(..., autoSend:)` orchestration returning either a task or run attempt.
- Modify `cursor_operator/Sources/CursorOperatorCLI/CursorOperatorCLI.swift` to add `--auto-send` on `task add` and run the add command asynchronously.
- Modify `cursor_operator/Tests/CursorOperatorCoreTests/CursorTaskCreationAndPreviewTests.swift` for draft persistence behavior.
- Modify `cursor_operator/Tests/CursorOperatorCoreTests/CursorBoardModelTests.swift` for GUI model auto-send behavior.
- Modify `cursor_operator/Tests/CursorOperatorCLICoreTests/CursorOperatorCLICommandsTests.swift` for CLI auto-send behavior.
- Modify `cursor_operator/Tests/CursorOperatorCLIIntegrationTests/CursorOperatorCLIBinaryTests.swift` for ArgumentParser validation and JSON error behavior.

## Task 1: Fix Existing SDK Helper Sanitize Test

**Files:**
- Modify: `cursor_operator/Resources/CursorSDKHelper/cursor-sdk-helper.mjs`
- Modify: `cursor_operator/Tests/CursorOperatorCoreTests/CursorCloudAgentSDKRuntimeTests.swift`

- [ ] **Step 1: Reproduce the focused baseline failure**

Run:

```bash
cd cursor_operator
/usr/bin/env HOME=/private/tmp CLANG_MODULE_CACHE_PATH=/private/tmp/clang-module-cache swift test --filter sdkHelperSanitizeErrorRedactsCursorAPIKeys
```

Expected: FAIL because the helper process exits `1` and stdout is empty when `@cursor/sdk` is not installed.

- [ ] **Step 2: Improve the failure diagnostic**

Change the test to decode stderr and include it in the expectation comments.

```swift
let stderrOutput = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
#expect(process.terminationStatus == 0, Comment(rawValue: stderrOutput))
#expect(output == "failed with crsr_[redacted]", Comment(rawValue: stderrOutput))
```

- [ ] **Step 3: Lazily import Cursor SDK only for actions that need it**

Replace the top-level SDK import with a dynamic import in `cursor-sdk-helper.mjs`.

```javascript
import { pathToFileURL } from "node:url";

async function cursorAgentClass() {
  const module = await import("@cursor/sdk");
  return module.Agent;
}
```

Then call it inside `startRun` and `waitForRun`.

```javascript
const Agent = await cursorAgentClass();
```

- [ ] **Step 4: Verify the focused test passes**

Run:

```bash
cd cursor_operator
/usr/bin/env HOME=/private/tmp CLANG_MODULE_CACHE_PATH=/private/tmp/clang-module-cache swift test --filter sdkHelperSanitizeErrorRedactsCursorAPIKeys
```

Expected: PASS.

## Task 2: Add Draft Auto-Send State and GUI Model Orchestration

**Files:**
- Modify: `cursor_operator/Sources/CursorOperatorCore/Models/CursorTaskCreation.swift`
- Modify: `cursor_operator/Sources/CursorOperatorCore/Models/CursorBoardModel.swift`
- Modify: `cursor_operator/Tests/CursorOperatorCoreTests/CursorTaskCreationAndPreviewTests.swift`
- Modify: `cursor_operator/Tests/CursorOperatorCoreTests/CursorBoardModelTests.swift`

- [ ] **Step 1: Write draft state test**

Add this test.

```swift
@Test func taskCreationDraftDefaultsAutoSendOffAndKeepsItOutOfStoredTask() throws {
    let draft = CursorTaskCreationDraft(autoSend: true)

    #expect(draft.autoSend)
}
```

Expected failure: `extra argument 'autoSend' in call`.

- [ ] **Step 2: Add `autoSend` to the draft**

Add the property and initializer parameter.

```swift
public var autoSend: Bool

public init(
    repositoryID: UUID? = nil,
    title: String = "",
    prompt: String = "",
    autoCreatePR: Bool = false,
    autoSend: Bool = false
) {
    self.repositoryID = repositoryID
    self.title = title
    self.prompt = prompt
    self.autoCreatePR = autoCreatePR
    self.autoSend = autoSend
}
```

- [ ] **Step 3: Write board model auto-send test**

Add an async test that fills `creationDraft.autoSend = true`, calls `createTaskFromDraftReportingErrors()`, waits for the fake runtime, and expects the task to become `.running`.

```swift
#expect(model.createTaskFromDraftReportingErrors())
try await waitUntil {
    try store.tasks().first?.status == .running
}
#expect(runtime.requests.count == 1)
```

Expected failure: the task remains `.ready`.

- [ ] **Step 4: Send after creating a new draft task**

Add `createTaskFromDraftReportingErrors` behavior that captures the created task and calls `sendReportingErrors(taskID:)` when the pre-reset draft requested auto-send.

```swift
let task = try createTaskFromDraft()
if shouldAutoSend {
    sendReportingErrors(taskID: task.id)
}
```

- [ ] **Step 5: Preserve edit semantics**

Ensure `prepareEditTaskDraftForPresentation` creates drafts with `autoSend: false`.
Ensure `updateTaskFromDraft` resets drafts with only `repositoryID`.

## Task 3: Add GUI Control

**Files:**
- Modify: `cursor_operator/Sources/CursorOperatorCore/Views/CursorOperatorRootView.swift`

- [ ] **Step 1: Add auto-send binding**

Add a binding mirroring the existing `autoCreatePRBinding`.

```swift
private var autoSendBinding: Binding<Bool> {
    Binding {
        model.creationDraft.autoSend
    } set: {
        model.creationDraft.autoSend = $0
    }
}
```

- [ ] **Step 2: Add checkbox only while creating**

In the sheet `HStack`, show:

```swift
if model.editingTaskID == nil {
    Toggle("Auto-send", isOn: autoSendBinding)
        .toggleStyle(.checkbox)
        .disabled(!model.setupStatus.canSend)
        .help(model.setupStatus.canSend ? "Send to Cursor immediately after creating the task." : model.setupStatus.sendDisabledReason)
}
```

Expected: Edit sheets do not expose a send side effect.

## Task 4: Add CLI Auto-Send

**Files:**
- Modify: `cursor_operator/Sources/CursorOperatorCLICore/CursorOperatorCLICommands.swift`
- Modify: `cursor_operator/Sources/CursorOperatorCLI/CursorOperatorCLI.swift`
- Modify: `cursor_operator/Tests/CursorOperatorCLICoreTests/CursorOperatorCLICommandsTests.swift`
- Modify: `cursor_operator/Tests/CursorOperatorCLIIntegrationTests/CursorOperatorCLIBinaryTests.swift`

- [ ] **Step 1: Write CLI core auto-send test**

Add an async test that calls the new async add method with `autoSend: true`.

```swift
let result = try await commands.addTask(
    repository: "operator",
    title: "File follow-up",
    prompt: "Do the thing",
    autoCreatePR: true,
    autoSend: true
)

#expect(result.runAttempt?.status == "succeeded")
#expect(try store.tasks().first?.status == .running)
#expect(runtime.requests.count == 1)
```

Expected failure: no async `addTask` overload exists.

- [ ] **Step 2: Add return envelope**

Add a Codable result that can contain either the created task or the run attempt.

```swift
public struct CursorCLITaskAddResult: Codable, Equatable, Sendable {
    public let task: CursorCLITask
    public let runAttempt: CursorCLIRunAttempt?
}
```

- [ ] **Step 3: Add async add orchestration**

Keep the existing synchronous add method for tests and callers, then add an async overload.

```swift
public func addTask(
    repository: String,
    title: String,
    prompt: String,
    autoCreatePR: Bool,
    autoSend: Bool
) async throws -> CursorCLITaskAddResult {
    let task = try addTask(repository: repository, title: title, prompt: prompt, autoCreatePR: autoCreatePR)
    guard autoSend else {
        return CursorCLITaskAddResult(task: task, runAttempt: nil)
    }
    let attempt = try await sendTask(id: task.id, wait: false)
    return CursorCLITaskAddResult(task: task, runAttempt: attempt)
}
```

- [ ] **Step 4: Add `--auto-send` to CLI parsing**

Make `TaskAdd` an `AsyncParsableCommand`, add:

```swift
@Flag(help: "Send the task to Cursor Cloud Agent immediately after creating it.")
var autoSend = false
```

Use the async overload and render task line for normal add, run line for auto-send.

- [ ] **Step 5: Add CLI integration validation**

Add a JSON usage test that `--auto-send` with missing credentials maps to `cursorUnavailable` after task creation.

Expected: exit code `4` and JSON error code `cursorUnavailable`.

## Task 5: Verification

**Files:**
- All modified files.

- [ ] **Step 1: Run focused tests**

Run:

```bash
cd cursor_operator
/usr/bin/env HOME=/private/tmp CLANG_MODULE_CACHE_PATH=/private/tmp/clang-module-cache swift test --filter CursorOperatorCoreTests
/usr/bin/env HOME=/private/tmp CLANG_MODULE_CACHE_PATH=/private/tmp/clang-module-cache swift test --filter CursorOperatorCLICoreTests
/usr/bin/env HOME=/private/tmp CLANG_MODULE_CACHE_PATH=/private/tmp/clang-module-cache swift test --filter CursorOperatorCLIIntegrationTests
```

Expected: PASS.

- [ ] **Step 2: Run full suite**

Run:

```bash
cd cursor_operator
/usr/bin/env HOME=/private/tmp CLANG_MODULE_CACHE_PATH=/private/tmp/clang-module-cache swift test
```

Expected: PASS.

- [ ] **Step 3: Inspect git diff**

Run:

```bash
git status --short
git diff -- cursor_operator docs/superpowers/plans/2026-06-24-cursor-auto-send.md
```

Expected: only feature and test files changed.

## Self-Review

Spec coverage: CLI task creation and GUI task creation both get an opt-in auto-send path.
Spec coverage: existing manual create and manual send remain available as independent operations.
Spec coverage: TDD starts with focused failing tests and uses existing public model and CLI interfaces.
Placeholder scan: no task uses TBD or vague implementation instructions.
Type consistency: `autoSend` is draft-only for GUI state, and `CursorCLITaskAddResult` carries the CLI task plus optional run attempt.
