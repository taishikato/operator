import Foundation
import Testing
@testable import OperatorDesktop

@Test func taskCreationDraftRequiresRepositoryTitleAndPromptAndDefaultsReasoningToMedium() throws {
    let store = try OperatorStore(databaseURL: temporaryDatabaseURL())
    let repository = try store.createRepository(name: "operator", path: "/tmp/operator", defaultBranch: "main")
    var draft = TaskCreationDraft()

    #expect(throws: TaskCreationError.repositoryRequired) {
        try draft.createTask(in: store)
    }

    draft.repositoryID = repository.id
    #expect(throws: TaskCreationError.titleRequired) {
        try draft.createTask(in: store)
    }

    draft.title = "  Build inspector  "
    #expect(throws: TaskCreationError.promptRequired) {
        try draft.createTask(in: store)
    }

    draft.prompt = "  Add the right-side inspector.  "
    let task = try draft.createTask(in: store)

    #expect(task.repositoryID == repository.id)
    #expect(task.title == "Build inspector")
    #expect(task.prompt == "Add the right-side inspector.")
    #expect(task.reasoningEffort == .medium)
    #expect(task.status == .ready)
    #expect(try store.tasks().map(\.id) == [task.id])
}

@Test func reasoningEffortOptionsExposeCodexLabelsAndInternalValues() {
    #expect(ReasoningEffortOption.all.map(\.label) == ["Low", "Medium", "High", "Extra High"])
    #expect(ReasoningEffortOption.all.map(\.effort) == [.low, .medium, .high, .xhigh])
    #expect(ReasoningEffort.xhigh.displayLabel == "Extra High")
}

@Test func boardProjectionGroupsActiveTasksAndExcludesArchived() throws {
    let store = try OperatorStore(databaseURL: temporaryDatabaseURL())
    let repository = try store.createRepository(name: "operator", path: "/tmp/operator", defaultBranch: "main")
    let readyTask = try store.createTask(repositoryID: repository.id, title: "Ready work", prompt: "Prompt", reasoningEffort: .high)
    let reviewTask = try store.createTask(repositoryID: repository.id, title: "Review work", prompt: "Prompt")
    _ = try store.recordSuccessfulRun(
        taskID: reviewTask.id,
        worktreePath: "/tmp/worktrees/review",
        baseBranch: "main",
        baseRef: "abc123",
        codexThreadID: "thread-review",
        codexThreadURL: nil
    )
    let doneCandidate = try store.createTask(repositoryID: repository.id, title: "Done work", prompt: "Prompt", reasoningEffort: .xhigh)
    _ = try store.recordSuccessfulRun(
        taskID: doneCandidate.id,
        worktreePath: "/tmp/worktrees/done",
        baseBranch: "main",
        baseRef: "def456",
        codexThreadID: "thread-done",
        codexThreadURL: nil
    )
    let doneTask = try store.markTaskDone(id: doneCandidate.id)
    let archivedTask = try store.createTask(repositoryID: repository.id, title: "Archived work", prompt: "Prompt")
    _ = try store.archiveTask(id: archivedTask.id)

    let projection = try TaskBoardProjection.load(from: store)

    #expect(projection.columns.map(\.id) == [.ready, .review, .done])
    #expect(projection.column(.ready).cards.map(\.id) == [readyTask.id])
    #expect(projection.column(.review).cards.map(\.id) == [reviewTask.id])
    #expect(projection.column(.done).cards.map(\.id) == [doneTask.id])
    #expect(projection.columns.flatMap(\.cards).map(\.title).contains("Archived work") == false)
}

@Test func boardProjectionExposesOpenInCodexForReviewAndDoneButNotReadyTasks() throws {
    let store = try OperatorStore(databaseURL: temporaryDatabaseURL())
    let repository = try store.createRepository(name: "operator", path: "/tmp/operator", defaultBranch: "main")
    let readyTask = try store.createTask(repositoryID: repository.id, title: "Ready work", prompt: "Prompt")
    let reviewTask = try store.createTask(repositoryID: repository.id, title: "Review work", prompt: "Prompt")
    let reviewURL = URL(string: "codex://thread/review")!
    _ = try store.recordSuccessfulRun(
        taskID: reviewTask.id,
        worktreePath: "/tmp/worktrees/review",
        baseBranch: "main",
        baseRef: "abc123",
        codexThreadID: "thread-review",
        codexThreadURL: reviewURL
    )
    let doneCandidate = try store.createTask(repositoryID: repository.id, title: "Done work", prompt: "Prompt")
    _ = try store.recordSuccessfulRun(
        taskID: doneCandidate.id,
        worktreePath: "/tmp/worktrees/done",
        baseBranch: "main",
        baseRef: "def456",
        codexThreadID: "thread-done",
        codexThreadURL: nil
    )
    let doneTask = try store.markTaskDone(id: doneCandidate.id)

    let projection = try TaskBoardProjection.load(from: store)
    let readyCard = try #require(projection.column(.ready).cards.first)
    let reviewCard = try #require(projection.column(.review).cards.first)
    let doneCard = try #require(projection.column(.done).cards.first)

    #expect(readyCard.id == readyTask.id)
    #expect(readyCard.canOpenInCodexApp == false)
    #expect(readyCard.codexOpenTarget == nil)
    #expect(reviewCard.id == reviewTask.id)
    #expect(reviewCard.canOpenInCodexApp)
    #expect(reviewCard.codexOpenLabel == "Open in Codex App")
    #expect(reviewCard.codexOpenTarget == .url(reviewURL))
    #expect(doneCard.id == doneTask.id)
    #expect(doneCard.canOpenInCodexApp)
    #expect(doneCard.codexOpenTarget == .worktree(URL(filePath: "/tmp/worktrees/done", directoryHint: .isDirectory)))
}

@Test func boardProjectionFiltersByRepositoryAndIncludesCardBadges() throws {
    let store = try OperatorStore(databaseURL: temporaryDatabaseURL())
    let operatorRepo = try store.createRepository(name: "operator", path: "/tmp/operator", defaultBranch: "main")
    let codexRepo = try store.createRepository(name: "codex", path: "/tmp/codex", defaultBranch: "main")
    let operatorTask = try store.createTask(
        repositoryID: operatorRepo.id,
        title: "Operator task",
        prompt: "Prompt",
        reasoningEffort: .xhigh
    )
    _ = try store.recordFailedRun(
        taskID: operatorTask.id,
        worktreePath: "/tmp/worktrees/failed",
        baseBranch: "main",
        baseRef: "abc123",
        errorMessage: "app-server rejected turn"
    )
    _ = try store.createTask(repositoryID: codexRepo.id, title: "Codex task", prompt: "Prompt", reasoningEffort: .low)

    let projection = try TaskBoardProjection.load(from: store, selectedRepositoryID: operatorRepo.id)
    let card = try #require(projection.column(.ready).cards.first)

    #expect(projection.repositoryFilters.map(\.name) == ["All Repositories", "operator", "codex"])
    #expect(projection.columns.flatMap(\.cards).map(\.title) == ["Operator task"])
    #expect(card.title == "Operator task")
    #expect(card.repositoryBadge == "operator")
    #expect(card.reasoningBadge == "Extra High")
    #expect(card.triggerStateBadge == "Failed to send")
    #expect(card.promptPreview == nil)
    #expect(card.canSendToCodex)
    #expect(card.codexSendLabel == "Send to Codex")
}

@Test func inspectorProjectionShowsPromptAndEditabilityOnlyForReadyTasks() throws {
    let store = try OperatorStore(databaseURL: temporaryDatabaseURL())
    let repository = try store.createRepository(name: "operator", path: "/tmp/operator", defaultBranch: "main")
    let readyTask = try store.createTask(repositoryID: repository.id, title: "Ready", prompt: "Ready prompt")
    let reviewTask = try store.createTask(repositoryID: repository.id, title: "Review", prompt: "Review prompt")
    _ = try store.recordSuccessfulRun(
        taskID: reviewTask.id,
        worktreePath: "/tmp/worktrees/review",
        baseBranch: "main",
        baseRef: "abc123",
        codexThreadID: "thread-review",
        codexThreadURL: nil
    )

    let projection = try TaskBoardProjection.load(from: store)
    let readyInspector = try #require(projection.inspector(taskID: readyTask.id))
    let reviewInspector = try #require(projection.inspector(taskID: reviewTask.id))

    #expect(readyInspector.prompt == "Ready prompt")
    #expect(readyInspector.isEditable)
    #expect(readyInspector.canSendToCodex)
    #expect(readyInspector.codexSendLabel == "Send to Codex")
    #expect(reviewInspector.prompt == "Review prompt")
    #expect(reviewInspector.isEditable == false)
    #expect(reviewInspector.canSendToCodex == false)
    #expect(reviewInspector.canOpenInCodexApp)
    #expect(reviewInspector.codexOpenLabel == "Open in Codex App")
}

@Test @MainActor func taskBoardModelOpensCodexTargetForReviewTask() async throws {
    let store = try OperatorStore(databaseURL: temporaryDatabaseURL())
    let repository = try store.createRepository(name: "operator", path: "/tmp/operator", defaultBranch: "main")
    let task = try store.createTask(repositoryID: repository.id, title: "Review", prompt: "Prompt")
    let threadURL = URL(string: "codex://thread/thread-1")!
    _ = try store.recordSuccessfulRun(
        taskID: task.id,
        worktreePath: "/tmp/worktrees/review",
        baseBranch: "main",
        baseRef: "abc123",
        codexThreadID: "thread-1",
        codexThreadURL: threadURL
    )
    let opener = RecordingCodexAppOpener()
    let model = TaskBoardModel(store: store, codexOpener: opener)
    try model.load()

    await model.openTaskInCodexAppReportingErrors(taskID: task.id)

    #expect(opener.openedTargets == [.url(threadURL)])
    #expect(model.errorMessage == nil)
}

@Test @MainActor func taskBoardModelReportsShortErrorWhenCodexOpenFails() async throws {
    let store = try OperatorStore(databaseURL: temporaryDatabaseURL())
    let repository = try store.createRepository(name: "operator", path: "/tmp/operator", defaultBranch: "main")
    let task = try store.createTask(repositoryID: repository.id, title: "Review", prompt: "Prompt")
    _ = try store.recordSuccessfulRun(
        taskID: task.id,
        worktreePath: "/tmp/worktrees/review",
        baseBranch: "main",
        baseRef: "abc123",
        codexThreadID: "thread-1",
        codexThreadURL: nil
    )
    let opener = FailingCodexAppOpener()
    let model = TaskBoardModel(store: store, codexOpener: opener)
    try model.load()

    await model.openTaskInCodexAppReportingErrors(taskID: task.id)

    #expect(opener.openedTargets == [.worktree(URL(filePath: "/tmp/worktrees/review", directoryHint: .isDirectory))])
    #expect(model.errorMessage == "Unable to open Codex App.")
}

@Test func taskBoardModelDoesNotBlockMainActorWhileOpeningCodex() async throws {
    let store = try OperatorStore(databaseURL: temporaryDatabaseURL())
    let repository = try store.createRepository(name: "operator", path: "/tmp/operator", defaultBranch: "main")
    let task = try store.createTask(repositoryID: repository.id, title: "Review", prompt: "Prompt")
    _ = try store.recordSuccessfulRun(
        taskID: task.id,
        worktreePath: "/tmp/worktrees/review",
        baseBranch: "main",
        baseRef: "abc123",
        codexThreadID: "thread-1",
        codexThreadURL: nil
    )
    let opener = HoldingCodexAppOpener()
    let model = await MainActor.run {
        let model = TaskBoardModel(store: store, codexOpener: opener)
        model.loadReportingErrors()
        return model
    }

    let openTask = Task {
        await model.openTaskInCodexAppReportingErrors(taskID: task.id)
    }
    await waitUntil { opener.didStartOpening }

    let mainActorPing = ThreadSafeFlag()
    let pingTask = Task {
        await MainActor.run {
            mainActorPing.set()
        }
    }
    try await Task.sleep(for: .milliseconds(50))

    #expect(mainActorPing.isSet)

    opener.complete()
    await openTask.value
    await pingTask.value
}

@Test func inspectorProjectionOnlyIncludesVisibleTasks() throws {
    let store = try OperatorStore(databaseURL: temporaryDatabaseURL())
    let operatorRepo = try store.createRepository(name: "operator", path: "/tmp/operator", defaultBranch: "main")
    let codexRepo = try store.createRepository(name: "codex", path: "/tmp/codex", defaultBranch: "main")
    let visibleTask = try store.createTask(repositoryID: operatorRepo.id, title: "Visible", prompt: "Prompt")
    let filteredTask = try store.createTask(repositoryID: codexRepo.id, title: "Filtered", prompt: "Prompt")
    let archivedTask = try store.createTask(repositoryID: operatorRepo.id, title: "Archived", prompt: "Prompt")
    _ = try store.archiveTask(id: archivedTask.id)

    let projection = try TaskBoardProjection.load(from: store, selectedRepositoryID: operatorRepo.id)

    #expect(projection.inspector(taskID: visibleTask.id) != nil)
    #expect(projection.inspector(taskID: filteredTask.id) == nil)
    #expect(projection.inspector(taskID: archivedTask.id) == nil)
}

@Test func inspectorDraftUpdatesReadyTaskThroughStoreAndRejectsImmutableTasks() throws {
    let store = try OperatorStore(databaseURL: temporaryDatabaseURL())
    let repository = try store.createRepository(name: "operator", path: "/tmp/operator", defaultBranch: "main")
    let readyTask = try store.createTask(repositoryID: repository.id, title: "Ready", prompt: "Original")
    let reviewTask = try store.createTask(repositoryID: repository.id, title: "Review", prompt: "Original")
    _ = try store.recordSuccessfulRun(
        taskID: reviewTask.id,
        worktreePath: "/tmp/worktrees/review",
        baseBranch: "main",
        baseRef: "abc123",
        codexThreadID: "thread-review",
        codexThreadURL: nil
    )
    var draft = TaskInspectorDraft(task: readyTask)
    draft.title = "  Edited  "
    draft.prompt = "  Edited prompt  "
    draft.reasoningEffort = .high

    let updatedTask = try draft.save(taskID: readyTask.id, in: store)

    #expect(updatedTask.title == "Edited")
    #expect(updatedTask.prompt == "Edited prompt")
    #expect(updatedTask.reasoningEffort == .high)
    #expect(try store.task(id: readyTask.id)?.title == "Edited")
    #expect(throws: TaskLifecycleError.taskIsImmutable) {
        try TaskInspectorDraft(task: reviewTask).save(taskID: reviewTask.id, in: store)
    }
}

@Test @MainActor func taskBoardModelCreatesSelectsAndUpdatesReadyTasks() throws {
    let store = try OperatorStore(databaseURL: temporaryDatabaseURL())
    let repository = try store.createRepository(name: "operator", path: "/tmp/operator", defaultBranch: "main")
    let model = TaskBoardModel(store: store)
    try model.load()

    model.creationDraft.repositoryID = repository.id
    model.creationDraft.title = "Create board"
    model.creationDraft.prompt = "Wire the live board"
    model.creationDraft.reasoningEffort = .low

    try model.createTask()
    let taskID = try #require(model.projection.column(.ready).cards.first?.id)

    #expect(model.selectedTaskID == taskID)
    #expect(model.inspectorDraft?.title == "Create board")

    model.inspectorDraft?.title = "Updated board"
    model.inspectorDraft?.prompt = "Updated prompt"
    model.inspectorDraft?.reasoningEffort = .high
    try model.saveSelectedInspectorTask()

    #expect(try store.task(id: taskID)?.title == "Updated board")
    #expect(model.projection.inspector(taskID: taskID)?.prompt == "Updated prompt")
    #expect(model.projection.inspector(taskID: taskID)?.reasoningEffort == .high)
}

@Test @MainActor func taskBoardModelClearsSelectionWhenSelectedTaskLeavesRepositoryFilter() throws {
    let store = try OperatorStore(databaseURL: temporaryDatabaseURL())
    let operatorRepo = try store.createRepository(name: "operator", path: "/tmp/operator", defaultBranch: "main")
    let codexRepo = try store.createRepository(name: "codex", path: "/tmp/codex", defaultBranch: "main")
    let operatorTask = try store.createTask(repositoryID: operatorRepo.id, title: "Operator task", prompt: "Prompt")
    _ = try store.createTask(repositoryID: codexRepo.id, title: "Codex task", prompt: "Prompt")
    let model = TaskBoardModel(store: store)
    try model.load()
    model.selectTask(operatorTask.id)

    model.selectRepository(codexRepo.id)

    #expect(model.selectedTaskID == nil)
    #expect(model.inspectorDraft == nil)
    #expect(model.projection.inspector(taskID: operatorTask.id) == nil)
}

@Test @MainActor func taskBoardModelKeepsCreationRepositoryIndependentFromFilter() throws {
    let store = try OperatorStore(databaseURL: temporaryDatabaseURL())
    let operatorRepo = try store.createRepository(name: "operator", path: "/tmp/operator", defaultBranch: "main")
    let codexRepo = try store.createRepository(name: "codex", path: "/tmp/codex", defaultBranch: "main")
    let model = TaskBoardModel(store: store)
    try model.load()

    model.creationDraft.repositoryID = codexRepo.id
    model.selectRepository(operatorRepo.id)

    #expect(model.creationDraft.repositoryID == codexRepo.id)
}

@Test @MainActor func taskBoardModelDoesNotSelectNewTaskHiddenByRepositoryFilter() throws {
    let store = try OperatorStore(databaseURL: temporaryDatabaseURL())
    let operatorRepo = try store.createRepository(name: "operator", path: "/tmp/operator", defaultBranch: "main")
    let codexRepo = try store.createRepository(name: "codex", path: "/tmp/codex", defaultBranch: "main")
    let model = TaskBoardModel(store: store)
    try model.load()
    model.selectRepository(operatorRepo.id)
    model.creationDraft.repositoryID = codexRepo.id
    model.creationDraft.title = "Hidden task"
    model.creationDraft.prompt = "Prompt"

    try model.createTask()

    #expect(model.selectedTaskID == nil)
    #expect(model.inspectorDraft == nil)
    #expect(model.projection.column(.ready).cards.map(\.title) == [])
}

@Test @MainActor func taskBoardModelPreservesUnsavedInspectorDraftAcrossReloadsForSameVisibleTask() throws {
    let store = try OperatorStore(databaseURL: temporaryDatabaseURL())
    let repository = try store.createRepository(name: "operator", path: "/tmp/operator", defaultBranch: "main")
    let task = try store.createTask(repositoryID: repository.id, title: "Original", prompt: "Original prompt")
    let model = TaskBoardModel(store: store)
    try model.load()
    model.selectTask(task.id)
    model.inspectorDraft?.title = "Unsaved title"
    model.inspectorDraft?.prompt = "Unsaved prompt"
    model.inspectorDraft?.reasoningEffort = .xhigh

    try model.load()

    #expect(model.selectedTaskID == task.id)
    #expect(model.inspectorDraft?.title == "Unsaved title")
    #expect(model.inspectorDraft?.prompt == "Unsaved prompt")
    #expect(model.inspectorDraft?.reasoningEffort == .xhigh)
}

@Test @MainActor func taskBoardModelRefreshesInspectorDraftAfterSuccessfulSave() throws {
    let store = try OperatorStore(databaseURL: temporaryDatabaseURL())
    let repository = try store.createRepository(name: "operator", path: "/tmp/operator", defaultBranch: "main")
    let task = try store.createTask(repositoryID: repository.id, title: "Original", prompt: "Original prompt")
    let model = TaskBoardModel(store: store)
    try model.load()
    model.selectTask(task.id)
    model.inspectorDraft?.title = "  Trimmed title  "
    model.inspectorDraft?.prompt = "  Trimmed prompt  "
    model.inspectorDraft?.reasoningEffort = .high

    try model.saveSelectedInspectorTask()

    #expect(model.selectedTaskID == task.id)
    #expect(model.inspectorDraft?.title == "Trimmed title")
    #expect(model.inspectorDraft?.prompt == "Trimmed prompt")
    #expect(model.inspectorDraft?.reasoningEffort == .high)
}

@Test @MainActor func taskBoardModelShowsSendingStateWhileCodexTriggerIsInProgress() async throws {
    let store = try OperatorStore(databaseURL: temporaryDatabaseURL())
    let repository = try store.createRepository(name: "operator", path: "/tmp/operator", defaultBranch: "main")
    let task = try store.createTask(repositoryID: repository.id, title: "Send", prompt: "Prompt")
    let trigger = HoldingCodexTaskSender()
    let model = TaskBoardModel(store: store, codexTrigger: trigger)
    try model.load()

    let send = Task {
        await model.sendTaskToCodexReportingErrors(taskID: task.id)
    }
    while trigger.requestedTaskIDs.isEmpty {
        await Task.yield()
    }

    #expect(model.sendingTaskIDs == [task.id])
    #expect(model.projection.column(.ready).cards.first?.codexSendLabel == "Sending...")
    #expect(model.projection.inspector(taskID: task.id)?.codexSendLabel == "Sending...")

    trigger.complete(
        try store.recordSuccessfulRun(
            taskID: task.id,
            worktreePath: "/tmp/worktree",
            baseBranch: "main",
            baseRef: "abc123",
            codexThreadID: "thread-1",
            codexThreadURL: nil
        )
    )
    await send.value

    #expect(model.sendingTaskIDs.isEmpty)
    #expect(model.projection.column(.ready).cards.isEmpty)
    #expect(model.projection.column(.review).cards.map(\.id) == [task.id])
}

@Test @MainActor func taskBoardModelKeepsReadyTaskAndReportsErrorWhenCodexTriggerFails() async throws {
    let store = try OperatorStore(databaseURL: temporaryDatabaseURL())
    let repository = try store.createRepository(name: "operator", path: "/tmp/operator", defaultBranch: "main")
    let task = try store.createTask(repositoryID: repository.id, title: "Send", prompt: "Prompt")
    let trigger = FailingCodexTaskSender(error: FakeBoardCodexError(message: "app-server unavailable"))
    let model = TaskBoardModel(store: store, codexTrigger: trigger)
    try model.load()

    await model.sendTaskToCodexReportingErrors(taskID: task.id)

    #expect(model.sendingTaskIDs.isEmpty)
    #expect(model.projection.column(.ready).cards.map(\.id) == [task.id])
    #expect(model.errorMessage == "app-server unavailable")
}

@Test @MainActor func taskBoardModelSavesInspectorDraftBeforeSendingSelectedTaskToCodex() async throws {
    let store = try OperatorStore(databaseURL: temporaryDatabaseURL())
    let repository = try store.createRepository(name: "operator", path: "/tmp/operator", defaultBranch: "main")
    let task = try store.createTask(repositoryID: repository.id, title: "Original", prompt: "Original prompt")
    let trigger = RecordingCodexTaskSender(store: store)
    let model = TaskBoardModel(store: store, codexTrigger: trigger)
    try model.load()
    model.selectTask(task.id)
    model.inspectorDraft?.title = "Edited"
    model.inspectorDraft?.prompt = "Edited prompt exactly"
    model.inspectorDraft?.reasoningEffort = .xhigh

    await model.sendSelectedInspectorTaskToCodexReportingErrors()

    #expect(trigger.requestedTaskIDs == [task.id])
    #expect(try store.task(id: task.id)?.title == "Edited")
    #expect(try store.task(id: task.id)?.prompt == "Edited prompt exactly")
    #expect(try store.task(id: task.id)?.reasoningEffort == .xhigh)
    #expect(model.projection.column(.review).cards.map(\.id) == [task.id])
}

private final class HoldingCodexTaskSender: CodexTaskSending, @unchecked Sendable {
    private(set) var requestedTaskIDs: [UUID] = []
    private var continuation: CheckedContinuation<OperatorRun, Error>?

    func sendTaskToCodex(taskID: UUID) async throws -> OperatorRun {
        requestedTaskIDs.append(taskID)
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func complete(_ run: OperatorRun) {
        continuation?.resume(returning: run)
    }
}

private final class FailingCodexTaskSender: CodexTaskSending, @unchecked Sendable {
    private let error: Error

    init(error: Error) {
        self.error = error
    }

    func sendTaskToCodex(taskID: UUID) async throws -> OperatorRun {
        throw error
    }
}

private final class RecordingCodexTaskSender: CodexTaskSending, @unchecked Sendable {
    private let store: OperatorStore
    private(set) var requestedTaskIDs: [UUID] = []

    init(store: OperatorStore) {
        self.store = store
    }

    func sendTaskToCodex(taskID: UUID) async throws -> OperatorRun {
        requestedTaskIDs.append(taskID)
        return try store.recordSuccessfulRun(
            taskID: taskID,
            worktreePath: "/tmp/worktree",
            baseBranch: "main",
            baseRef: "abc123",
            codexThreadID: "thread-1",
            codexThreadURL: nil
        )
    }
}

private final class RecordingCodexAppOpener: CodexAppOpening, @unchecked Sendable {
    private(set) var openedTargets: [CodexOpenTarget] = []

    func open(_ target: CodexOpenTarget) throws {
        openedTargets.append(target)
    }
}

private final class FailingCodexAppOpener: CodexAppOpening, @unchecked Sendable {
    private(set) var openedTargets: [CodexOpenTarget] = []

    func open(_ target: CodexOpenTarget) throws {
        openedTargets.append(target)
        throw CodexAppOpenError.openFailed
    }
}

private final class HoldingCodexAppOpener: CodexAppOpening, @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var startedOpening = false

    var didStartOpening: Bool {
        lock.withLock {
            startedOpening
        }
    }

    func open(_ target: CodexOpenTarget) throws {
        lock.withLock {
            startedOpening = true
        }
        semaphore.wait()
    }

    func complete() {
        semaphore.signal()
    }
}

private final class ThreadSafeFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool {
        lock.withLock {
            value
        }
    }

    func set() {
        lock.withLock {
            value = true
        }
    }
}

private func waitUntil(
    timeout: Duration = .seconds(1),
    condition: @escaping @Sendable () -> Bool
) async {
    let start = ContinuousClock.now
    while !condition(), start.duration(to: .now) < timeout {
        await Task.yield()
    }
}

private struct FakeBoardCodexError: Error, LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}

private func temporaryDatabaseURL() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "TaskBoardModelTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appending(path: "operator.sqlite")
}
