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
    #expect(reviewInspector.prompt == "Review prompt")
    #expect(reviewInspector.isEditable == false)
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

private func temporaryDatabaseURL() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "TaskBoardModelTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appending(path: "operator.sqlite")
}
