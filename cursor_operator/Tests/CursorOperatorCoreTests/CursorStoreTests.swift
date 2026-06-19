import Foundation
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
        prompt: "Add SQLite persistence"
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
    #expect(try reloadedStore.runAttempts(taskID: task.id).map(\.status) == [.failed, .succeeded])
    #expect(try reloadedStore.runAttempts(taskID: task.id).last?.id == run.id)
    #expect(try reloadedStore.runAttempts(taskID: task.id).last?.cursorRunID == "run-123")
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

private func temporaryDatabaseURL() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "CursorOperatorStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appending(path: "cursor-operator.sqlite")
}
