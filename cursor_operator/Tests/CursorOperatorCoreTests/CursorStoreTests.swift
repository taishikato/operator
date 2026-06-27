import Foundation
import GRDB
import Testing
@testable import CursorOperatorCore

@Test func storePersistsRepositoriesTasksAndRunAttemptsAcrossReload() throws {
    let databaseURL = try temporaryDatabaseURL()
    let store = try CursorOperatorStore(databaseURL: databaseURL)
    let repository = try store.createRepository(
        name: "operator",
        localPath: "/tmp/operator",
        githubURL: URL(string: "https://github.com/example/operator")!,
        defaultBranch: "main"
    )
    let task = try store.createTask(
        repositoryID: repository.id,
        title: "Persist cursor lifecycle",
        prompt: "Add SQLite persistence",
        reasoningEffort: .high,
        useFastModel: true,
        harness: .codex
    )
    _ = try store.recordFailedSendAttempt(
        taskID: task.id,
        repositoryURL: repository.githubURL,
        startingRef: repository.defaultBranch,
        model: CursorModel.fixed,
        autoCreatePR: false,
        prompt: task.prompt,
        errorMessage: "Validation failed"
    )
    let run = try store.recordSuccessfulSendAttempt(
        taskID: task.id,
        repositoryURL: repository.githubURL,
        startingRef: repository.defaultBranch,
        model: CursorModel.fixed,
        autoCreatePR: false,
        prompt: task.prompt,
        cursorAgentID: "agent-123",
        cursorRunID: "run-123",
        cursorURL: URL(string: "https://cursor.com/agents/agent-123")!
    )

    let reloadedStore = try CursorOperatorStore(databaseURL: databaseURL)

    #expect(FileManager.default.fileExists(atPath: databaseURL.path))
    #expect(try reloadedStore.repositories().map(\.id) == [repository.id])
    #expect(try reloadedStore.tasks().map(\.id) == [task.id])
    #expect(try reloadedStore.task(id: task.id)?.status == .running)
    #expect(try reloadedStore.task(id: task.id)?.reasoningEffort == .high)
    #expect(try reloadedStore.task(id: task.id)?.useFastModel == true)
    #expect(try reloadedStore.task(id: task.id)?.harness == .codex)
    #expect(try reloadedStore.runAttempts(taskID: task.id).map(\.status) == [.failed, .succeeded])
    #expect(try reloadedStore.runAttempts(taskID: task.id).last?.id == run.id)
    #expect(try reloadedStore.runAttempts(taskID: task.id).last?.cursorRunID == "run-123")
}

@Test func migrationBackfillsLegacyTasksWithHarnessConfigurationDefaults() throws {
    let databaseURL = try temporaryDatabaseURL()
    let taskID = UUID()

    // Build a database at the schema that predates the harness configuration columns and
    // seed a legacy task row, before any connection runs the new migration.
    try seedLegacyTaskPredatingHarnessConfiguration(at: databaseURL, taskID: taskID)

    // Opening the store applies the remaining migrations, including addTaskHarnessConfiguration,
    // against the pre-existing row.
    let store = try CursorOperatorStore(databaseURL: databaseURL)
    let task = try #require(try store.task(id: taskID))

    // Pre-existing rows must be backfilled with the documented defaults.
    #expect(task.reasoningEffort == .medium)
    #expect(task.useFastModel == false)
    #expect(task.harness == .cursor)

    // Columns that existed before the migration must survive untouched.
    #expect(task.title == "Legacy task")
    #expect(task.autoCreatePR == true)
    #expect(task.status == .ready)
}

@Test func storeAllowsReadyEditsAndRejectsImmutableTaskEdits() throws {
    let store = try CursorOperatorStore(databaseURL: temporaryDatabaseURL())
    let repository = try store.createRepository(
        name: "operator",
        localPath: "/tmp/operator",
        githubURL: URL(string: "https://github.com/example/operator")!,
        defaultBranch: "main"
    )
    let task = try store.createTask(repositoryID: repository.id, title: "Original", prompt: "Prompt")

    let edited = try store.updateTaskContent(id: task.id, title: "Edited", prompt: "Edited prompt")
    #expect(edited.title == "Edited")
    #expect(edited.prompt == "Edited prompt")

    _ = try store.recordSuccessfulSendAttempt(
        taskID: task.id,
        repositoryURL: repository.githubURL,
        startingRef: repository.defaultBranch,
        model: CursorModel.fixed,
        autoCreatePR: false,
        prompt: edited.prompt,
        cursorAgentID: "agent-123",
        cursorRunID: "run-123",
        cursorURL: URL(string: "https://cursor.com/agents/agent-123")!
    )

    #expect(throws: CursorTaskLifecycleError.taskIsImmutable) {
        try store.updateTaskContent(id: task.id, title: "Too late", prompt: "Nope")
    }
}

@Test func storeArchivesActiveTasksAndHidesArchivedTasksFromBoardProjection() throws {
    let store = try CursorOperatorStore(databaseURL: temporaryDatabaseURL())
    let repository = try store.createRepository(
        name: "operator",
        localPath: "/tmp/operator",
        githubURL: URL(string: "https://github.com/example/operator")!,
        defaultBranch: "main"
    )
    let readyTask = try store.createTask(repositoryID: repository.id, title: "Archive me", prompt: "Prompt")
    let visibleTask = try store.createTask(repositoryID: repository.id, title: "Keep me", prompt: "Prompt")

    let archivedTask = try store.archiveTask(id: readyTask.id)
    let projection = try CursorBoardProjection.load(from: store)

    #expect(archivedTask.status == .archived)
    #expect(projection.columns.flatMap(\.cards).map(\.id) == [visibleTask.id])
}

@Test func boardProjectionExposesCursorReferencesForSentRunningDoneAndArchivedTasks() throws {
    let store = try CursorOperatorStore(databaseURL: temporaryDatabaseURL())
    let repository = try store.createRepository(
        name: "operator",
        localPath: "/tmp/operator",
        githubURL: URL(string: "https://github.com/example/operator")!,
        defaultBranch: "main"
    )
    let runningTask = try store.createTask(repositoryID: repository.id, title: "Running", prompt: "Prompt")
    _ = try store.recordSuccessfulSendAttempt(
        taskID: runningTask.id,
        repositoryURL: repository.githubURL,
        startingRef: repository.defaultBranch,
        model: CursorModel.fixed,
        autoCreatePR: false,
        prompt: runningTask.prompt,
        cursorAgentID: "agent-running",
        cursorRunID: "run-running",
        cursorURL: URL(string: "https://cursor.com/agents/agent-running")!
    )
    let doneTask = try store.createTask(repositoryID: repository.id, title: "Done", prompt: "Prompt")
    _ = try store.recordSuccessfulSendAttempt(
        taskID: doneTask.id,
        repositoryURL: repository.githubURL,
        startingRef: repository.defaultBranch,
        model: CursorModel.fixed,
        autoCreatePR: false,
        prompt: doneTask.prompt,
        cursorAgentID: "agent-done",
        cursorRunID: "run-done",
        cursorURL: URL(string: "https://cursor.com/agents/agent-done")!
    )
    _ = try store.markTaskDone(id: doneTask.id)
    let archivedTask = try store.createTask(repositoryID: repository.id, title: "Archived", prompt: "Prompt")
    _ = try store.recordSuccessfulSendAttempt(
        taskID: archivedTask.id,
        repositoryURL: repository.githubURL,
        startingRef: repository.defaultBranch,
        model: CursorModel.fixed,
        autoCreatePR: false,
        prompt: archivedTask.prompt,
        cursorAgentID: "agent-archived",
        cursorRunID: "run-archived",
        cursorURL: URL(string: "https://cursor.com/agents/agent-archived")!
    )
    _ = try store.archiveTask(id: archivedTask.id)

    let projection = try CursorBoardProjection.load(from: store)
    let activeCards = projection.columns.flatMap(\.cards)

    #expect(activeCards.first { $0.id == runningTask.id }?.canOpenInCursor == true)
    #expect(activeCards.first { $0.id == doneTask.id }?.canOpenInCursor == true)
    #expect(projection.archivedCards.first { $0.id == archivedTask.id }?.canOpenInCursor == true)
    #expect(projection.archivedCards.first { $0.id == archivedTask.id }?.cursorURL == URL(string: "https://cursor.com/agents/agent-archived")!)
}

@Test func storePreventsRerunAfterOneSuccessfulSendButAllowsFailedRetries() throws {
    let store = try CursorOperatorStore(databaseURL: temporaryDatabaseURL())
    let repository = try store.createRepository(
        name: "operator",
        localPath: "/tmp/operator",
        githubURL: URL(string: "https://github.com/example/operator")!,
        defaultBranch: "main"
    )
    let task = try store.createTask(repositoryID: repository.id, title: "Retry", prompt: "Prompt")

    _ = try store.recordFailedSendAttempt(
        taskID: task.id,
        repositoryURL: repository.githubURL,
        startingRef: repository.defaultBranch,
        model: CursorModel.fixed,
        autoCreatePR: false,
        prompt: task.prompt,
        errorMessage: "first failure"
    )
    _ = try store.recordFailedSendAttempt(
        taskID: task.id,
        repositoryURL: repository.githubURL,
        startingRef: repository.defaultBranch,
        model: CursorModel.fixed,
        autoCreatePR: false,
        prompt: task.prompt,
        errorMessage: "second failure"
    )
    _ = try store.recordSuccessfulSendAttempt(
        taskID: task.id,
        repositoryURL: repository.githubURL,
        startingRef: repository.defaultBranch,
        model: CursorModel.fixed,
        autoCreatePR: false,
        prompt: task.prompt,
        cursorAgentID: "agent-123",
        cursorRunID: "run-123",
        cursorURL: URL(string: "https://cursor.com/agents/agent-123")!
    )

    #expect(try store.runAttempts(taskID: task.id).map(\.status) == [.failed, .failed, .succeeded])
    #expect(throws: CursorTaskLifecycleError.taskAlreadyHasSuccessfulRun) {
        try store.recordSuccessfulSendAttempt(
            taskID: task.id,
            repositoryURL: repository.githubURL,
            startingRef: repository.defaultBranch,
            model: CursorModel.fixed,
            autoCreatePR: false,
            prompt: task.prompt,
            cursorAgentID: "agent-456",
            cursorRunID: "run-456",
            cursorURL: URL(string: "https://cursor.com/agents/agent-456")!
        )
    }
}

@Test func failedClaimedSendMovesTaskToFailed() throws {
    let store = try CursorOperatorStore(databaseURL: temporaryDatabaseURL())
    let repository = try store.createRepository(
        name: "operator",
        localPath: "/tmp/operator",
        githubURL: URL(string: "https://github.com/example/operator")!,
        defaultBranch: "main"
    )
    let task = try store.createTask(repositoryID: repository.id, title: "Fail claimed send", prompt: "Prompt")
    let claim = try store.claimSendAttempt(
        taskID: task.id,
        repositoryURL: repository.githubURL,
        startingRef: repository.defaultBranch,
        model: CursorModel.fixed,
        autoCreatePR: false,
        prompt: task.prompt
    )

    _ = try store.recordFailedClaimedSendAttempt(id: claim.id, errorMessage: "Provider failed")

    #expect(try store.task(id: task.id)?.status == .failed)
}

@Test func storeExpiresStalePendingSendClaimsBeforeRetry() throws {
    let store = try CursorOperatorStore(databaseURL: temporaryDatabaseURL())
    let repository = try store.createRepository(
        name: "operator",
        localPath: "/tmp/operator",
        githubURL: URL(string: "https://github.com/example/operator")!,
        defaultBranch: "main"
    )
    let task = try store.createTask(repositoryID: repository.id, title: "Retry stale pending", prompt: "Prompt")
    let now = Date(timeIntervalSince1970: 1_000)
    let staleDate = now.addingTimeInterval(-3_600)

    _ = try store.claimSendAttempt(
        taskID: task.id,
        repositoryURL: repository.githubURL,
        startingRef: repository.defaultBranch,
        model: CursorModel.fixed,
        autoCreatePR: false,
        prompt: task.prompt,
        now: staleDate,
        stalePendingAge: 60
    )

    let retryClaim = try store.claimSendAttempt(
        taskID: task.id,
        repositoryURL: repository.githubURL,
        startingRef: repository.defaultBranch,
        model: CursorModel.fixed,
        autoCreatePR: false,
        prompt: task.prompt,
        now: now,
        stalePendingAge: 60
    )

    let attempts = try store.runAttempts(taskID: task.id)
    #expect(attempts.map(\.status) == [.failed, .pending])
    #expect(attempts.first?.errorMessage == "Previous Cursor send was interrupted before Cursor returned a run reference.")
    #expect(attempts.last?.id == retryClaim.id)
}

// Migrates a fresh database up to the last migration that predates the harness configuration
// columns, then inserts a task row using only the columns that existed at that point. The raw
// connection is released when this function returns so the store can reopen the file cleanly.
private func seedLegacyTaskPredatingHarnessConfiguration(at databaseURL: URL, taskID: UUID) throws {
    let queue = try DatabaseQueue(path: databaseURL.path)
    try CursorOperatorStore.migrator.migrate(queue, upTo: "addActiveSendAttemptGuard")

    let repositoryID = UUID()
    try queue.write { db in
        try db.execute(
            sql: """
                INSERT INTO repositories (id, name, localPath, githubURL, defaultBranch, createdAt, updatedAt)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                repositoryID.uuidString,
                "operator",
                "/tmp/operator",
                "https://github.com/example/operator",
                "main",
                0.0,
                0.0
            ]
        )
        try db.execute(
            sql: """
                INSERT INTO tasks (id, repositoryID, title, prompt, autoCreatePR, status, createdAt, updatedAt)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                taskID.uuidString,
                repositoryID.uuidString,
                "Legacy task",
                "Legacy prompt",
                true,
                "ready",
                0.0,
                0.0
            ]
        )
    }
}

private func temporaryDatabaseURL() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "CursorOperatorStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appending(path: "operator.sqlite")
}
