import Foundation
import Combine
import GRDB
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

@Test func storeReturnsLatestRunsForAllTasksInOneCall() throws {
    let store = try OperatorStore(databaseURL: temporaryDatabaseURL())
    let repository = try store.createRepository(name: "operator", path: "/tmp/operator", defaultBranch: "main")
    let taskWithRuns = try store.createTask(repositoryID: repository.id, title: "With runs", prompt: "Prompt")
    let taskWithoutRuns = try store.createTask(repositoryID: repository.id, title: "Without runs", prompt: "Prompt")
    let firstRun = try store.recordFailedRun(
        taskID: taskWithRuns.id,
        worktreePath: "/tmp/worktrees/failed",
        baseBranch: "main",
        baseRef: "abc123",
        errorMessage: "failed",
        now: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let latestRun = try store.recordSuccessfulRun(
        taskID: taskWithRuns.id,
        worktreePath: "/tmp/worktrees/success",
        baseBranch: "main",
        baseRef: "def456",
        codexThreadID: "thread-1",
        codexThreadURL: nil,
        now: Date(timeIntervalSince1970: 1_700_000_100)
    )

    let latestRuns = try store.latestRunsByTaskID()

    #expect(latestRuns[taskWithRuns.id]?.id == latestRun.id)
    #expect(latestRuns[taskWithRuns.id]?.id != firstRun.id)
    #expect(latestRuns[taskWithoutRuns.id] == nil)
}

@Test func storePublishesChangesForBoardReloadsAfterMutations() throws {
    let store = try OperatorStore(databaseURL: temporaryDatabaseURL())
    var changeCount = 0
    let cancellable = store.changes.sink {
        changeCount += 1
    }
    defer { cancellable.cancel() }

    let repository = try store.createRepository(name: "operator", path: "/tmp/operator", defaultBranch: "main")
    let task = try store.createTask(repositoryID: repository.id, title: "Task", prompt: "Prompt")
    _ = try store.updateTaskContent(id: task.id, title: "Edited", prompt: "Prompt", reasoningEffort: .high)

    #expect(changeCount == 3)
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

@Test func storeRejectsDuplicateRepositoryPathsPredictably() throws {
    let store = try OperatorStore(databaseURL: temporaryDatabaseURL())
    let repository = try store.createRepository(name: "operator", path: "/tmp/operator", defaultBranch: "main")

    #expect(throws: OperatorStoreError.repositoryPathAlreadyRegistered(existingID: repository.id)) {
        try store.createRepository(name: "Operator Copy", path: "/tmp/operator", defaultBranch: "feature/desktop")
    }

    let error = OperatorStoreError.repositoryPathAlreadyRegistered(existingID: repository.id)
    #expect(error.errorDescription == "This repository is already registered.")
    #expect(try store.repositories().map(\.id) == [repository.id])
}

@Test func storeAddsRepositoryPathIndexToExistingDesktopDatabases() throws {
    let databaseURL = try temporaryDatabaseURL()
    let dbQueue = try DatabaseQueue(path: databaseURL.path)
    try dbQueue.write { db in
        try createLegacyDesktopSchema(in: db)
        try db.execute(sql: "INSERT INTO grdb_migrations (identifier) VALUES ('createOperatorDesktopMVPStore')")
    }

    _ = try OperatorStore(databaseURL: databaseURL)

    let hasRepositoryPathIndex = try dbQueue.read { db in
        try Bool.fetchOne(
            db,
            sql: """
                SELECT EXISTS(
                    SELECT 1 FROM sqlite_master
                    WHERE type = 'index' AND name = 'repositories_on_path'
                )
                """
        ) ?? false
    }
    #expect(hasRepositoryPathIndex)
}

@Test func storeUpdatesRepositoryDefaultBranchWithoutChangingCreatedAt() throws {
    let store = try OperatorStore(databaseURL: temporaryDatabaseURL())
    let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
    let updatedAt = Date(timeIntervalSince1970: 1_700_000_500)
    let repository = try store.createRepository(
        name: "operator",
        path: "/tmp/operator",
        defaultBranch: "main",
        now: createdAt
    )

    let updatedRepository = try store.updateRepositoryDefaultBranch(
        id: repository.id,
        defaultBranch: "feature/desktop",
        now: updatedAt
    )

    #expect(updatedRepository.defaultBranch == "feature/desktop")
    #expect(updatedRepository.createdAt == createdAt)
    #expect(updatedRepository.updatedAt == updatedAt)
    #expect(try store.repositories().first?.defaultBranch == "feature/desktop")
}

private func temporaryDatabaseURL() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "OperatorStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appending(path: "operator.sqlite")
}

private func createLegacyDesktopSchema(in db: Database) throws {
    try db.create(table: "repositories") { table in
        table.column("id", .text).primaryKey()
        table.column("name", .text).notNull()
        table.column("path", .text).notNull()
        table.column("defaultBranch", .text).notNull()
        table.column("createdAt", .double).notNull()
        table.column("updatedAt", .double).notNull()
    }

    try db.create(table: "tasks") { table in
        table.column("id", .text).primaryKey()
        table.column("repositoryID", .text).notNull().references("repositories", onDelete: .restrict)
        table.column("title", .text).notNull()
        table.column("prompt", .text).notNull()
        table.column("reasoningEffort", .text).notNull()
        table.column("status", .text).notNull()
        table.column("createdAt", .double).notNull()
        table.column("updatedAt", .double).notNull()
    }

    try db.create(table: "runs") { table in
        table.column("id", .text).primaryKey()
        table.column("taskID", .text).notNull().references("tasks", onDelete: .restrict)
        table.column("repositoryID", .text).notNull().references("repositories", onDelete: .restrict)
        table.column("status", .text).notNull()
        table.column("worktreePath", .text).notNull()
        table.column("baseBranch", .text).notNull()
        table.column("baseRef", .text).notNull()
        table.column("codexThreadID", .text)
        table.column("codexThreadURL", .text)
        table.column("errorMessage", .text)
        table.column("createdAt", .double).notNull()
        table.column("completedAt", .double)
    }

    try db.create(index: "tasks_on_repositoryID", on: "tasks", columns: ["repositoryID"])
    try db.create(index: "runs_on_taskID", on: "runs", columns: ["taskID"])
    try db.execute(sql: "CREATE UNIQUE INDEX runs_one_success_per_task ON runs(taskID) WHERE status = 'triggered'")

    try db.create(table: "grdb_migrations") { table in
        table.column("identifier", .text).primaryKey()
    }
}
