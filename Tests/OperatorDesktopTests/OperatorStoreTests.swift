import Foundation
import Testing
@testable import OperatorDesktop

@Test func storeInitializesSQLiteAndReloadsRepositoriesTasksAndRuns() throws {
    let databaseURL = try temporaryDatabaseURL()
    let store = try OperatorStore(databaseURL: databaseURL)

    let repository = try store.createRepository(
        name: "operator",
        path: "/tmp/operator",
        defaultBranch: "feature/desktop"
    )
    let task = try store.createTask(
        repositoryID: repository.id,
        title: "Persist lifecycle",
        prompt: "Add GRDB persistence"
    )
    _ = try store.recordFailedRun(
        taskID: task.id,
        worktreePath: "/tmp/worktrees/failed",
        baseBranch: "feature/desktop",
        baseRef: "abc123",
        errorMessage: "app-server rejected turn"
    )
    let successfulRun = try store.recordSuccessfulRun(
        taskID: task.id,
        worktreePath: "/tmp/worktrees/success",
        baseBranch: "feature/desktop",
        baseRef: "def456",
        codexThreadID: "thread-1",
        codexThreadURL: URL(string: "codex://thread/thread-1")
    )

    let reloadedStore = try OperatorStore(databaseURL: databaseURL)

    #expect(FileManager.default.fileExists(atPath: databaseURL.path))
    #expect(try reloadedStore.repositories().map(\.id) == [repository.id])
    #expect(try reloadedStore.tasks().map(\.id) == [task.id])
    #expect(try reloadedStore.task(id: task.id)?.status == .review)
    #expect(try reloadedStore.runs(taskID: task.id).map(\.status) == [.triggerFailed, .triggered])
    #expect(try reloadedStore.runs(taskID: task.id).last?.id == successfulRun.id)
}

@Test func storeEnforcesManualLifecycleTransitions() throws {
    let store = try OperatorStore(databaseURL: temporaryDatabaseURL())
    let repository = try store.createRepository(name: "operator", path: "/tmp/operator", defaultBranch: "main")
    let readyTask = try store.createTask(repositoryID: repository.id, title: "Archive ready", prompt: "Prompt")

    let archivedReadyTask = try store.archiveTask(id: readyTask.id)
    #expect(archivedReadyTask.status == .archived)

    let reviewTask = try store.createTask(repositoryID: repository.id, title: "Move to done", prompt: "Prompt")
    _ = try store.recordSuccessfulRun(
        taskID: reviewTask.id,
        worktreePath: "/tmp/worktrees/review",
        baseBranch: "main",
        baseRef: "abc123",
        codexThreadID: "thread-2",
        codexThreadURL: nil
    )
    let doneTask = try store.markTaskDone(id: reviewTask.id)
    #expect(doneTask.status == .done)
    #expect(try store.archiveTask(id: reviewTask.id).status == .archived)

    let archivedFromReview = try store.createTask(repositoryID: repository.id, title: "Archive review", prompt: "Prompt")
    _ = try store.recordSuccessfulRun(
        taskID: archivedFromReview.id,
        worktreePath: "/tmp/worktrees/archive-review",
        baseBranch: "main",
        baseRef: "def456",
        codexThreadID: "thread-3",
        codexThreadURL: nil
    )
    #expect(try store.archiveTask(id: archivedFromReview.id).status == .archived)
}

@Test func storeRejectsReadyReversalAndImmutableTaskContent() throws {
    let store = try OperatorStore(databaseURL: temporaryDatabaseURL())
    let repository = try store.createRepository(name: "operator", path: "/tmp/operator", defaultBranch: "main")
    let task = try store.createTask(repositoryID: repository.id, title: "Immutable", prompt: "Original prompt")
    _ = try store.recordSuccessfulRun(
        taskID: task.id,
        worktreePath: "/tmp/worktrees/immutable",
        baseBranch: "main",
        baseRef: "abc123",
        codexThreadID: "thread-4",
        codexThreadURL: nil
    )

    #expect(throws: TaskLifecycleError.transitionNotAllowed) {
        try store.assertTaskReady(id: task.id)
    }
    #expect(throws: TaskLifecycleError.taskIsImmutable) {
        try store.updateTaskContent(
            id: task.id,
            title: "Edited",
            prompt: "Edited prompt",
            reasoningEffort: .high
        )
    }
}

@Test func storeRejectsInvalidManualTransitions() throws {
    let store = try OperatorStore(databaseURL: temporaryDatabaseURL())
    let repository = try store.createRepository(name: "operator", path: "/tmp/operator", defaultBranch: "main")
    let readyTask = try store.createTask(repositoryID: repository.id, title: "Ready", prompt: "Prompt")

    #expect(throws: TaskLifecycleError.transitionNotAllowed) {
        try store.markTaskDone(id: readyTask.id)
    }

    let archivedTask = try store.archiveTask(id: readyTask.id)
    #expect(throws: TaskLifecycleError.transitionNotAllowed) {
        try store.archiveTask(id: archivedTask.id)
    }
    #expect(throws: TaskLifecycleError.transitionNotAllowed) {
        try store.assertTaskReady(id: archivedTask.id)
    }

    let doneCandidate = try store.createTask(repositoryID: repository.id, title: "Done", prompt: "Prompt")
    _ = try store.recordSuccessfulRun(
        taskID: doneCandidate.id,
        worktreePath: "/tmp/worktrees/done",
        baseBranch: "main",
        baseRef: "abc123",
        codexThreadID: "thread-done",
        codexThreadURL: nil
    )
    let doneTask = try store.markTaskDone(id: doneCandidate.id)
    #expect(throws: TaskLifecycleError.transitionNotAllowed) {
        try store.assertTaskReady(id: doneTask.id)
    }
}

@Test func assertingReadyTaskDoesNotUpdateStoredTimestamp() throws {
    let store = try OperatorStore(databaseURL: temporaryDatabaseURL())
    let repository = try store.createRepository(name: "operator", path: "/tmp/operator", defaultBranch: "main")
    let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
    let task = try store.createTask(
        repositoryID: repository.id,
        title: "Ready",
        prompt: "Prompt",
        now: createdAt
    )

    let readyTask = try store.assertTaskReady(id: task.id)

    #expect(readyTask.status == .ready)
    #expect(readyTask.updatedAt == createdAt)
    #expect(try store.task(id: task.id)?.updatedAt == createdAt)
}

@Test func storeAllowsFailedRunsBeforeOneSuccessfulRunOnly() throws {
    let store = try OperatorStore(databaseURL: temporaryDatabaseURL())
    let repository = try store.createRepository(name: "operator", path: "/tmp/operator", defaultBranch: "main")
    let task = try store.createTask(repositoryID: repository.id, title: "Retry", prompt: "Prompt")

    _ = try store.recordFailedRun(
        taskID: task.id,
        worktreePath: "/tmp/worktrees/failed-1",
        baseBranch: "main",
        baseRef: "abc123",
        errorMessage: "first failure"
    )
    _ = try store.recordFailedRun(
        taskID: task.id,
        worktreePath: "/tmp/worktrees/failed-2",
        baseBranch: "main",
        baseRef: "abc123",
        errorMessage: "second failure"
    )
    _ = try store.recordSuccessfulRun(
        taskID: task.id,
        worktreePath: "/tmp/worktrees/success",
        baseBranch: "main",
        baseRef: "def456",
        codexThreadID: "thread-5",
        codexThreadURL: nil
    )

    #expect(try store.task(id: task.id)?.status == .review)
    #expect(try store.runs(taskID: task.id).map(\.status) == [.triggerFailed, .triggerFailed, .triggered])
    #expect(throws: TaskLifecycleError.taskAlreadyHasSuccessfulRun) {
        try store.recordSuccessfulRun(
            taskID: task.id,
            worktreePath: "/tmp/worktrees/second-success",
            baseBranch: "main",
            baseRef: "fedcba",
            codexThreadID: "thread-6",
            codexThreadURL: nil
        )
    }
}

private func temporaryDatabaseURL() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "OperatorStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appending(path: "operator.sqlite")
}
