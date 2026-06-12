import Foundation
import Testing
import OperatorDesktop
@testable import OperatorCLICore

// MARK: - repo list

@Test func repoListReturnsRegisteredRepositories() throws {
    let store = try temporaryStore()
    let repository = try store.createRepository(name: "operator", path: "/tmp/operator", defaultBranch: "main")
    let commands = OperatorCLICommands(store: store)

    let repositories = try commands.listRepositories()

    #expect(repositories.map(\.id) == [repository.id.uuidString])
    #expect(repositories.first?.name == "operator")
    #expect(repositories.first?.defaultBranch == "main")
}

// MARK: - task add

@Test func taskAddCreatesReadyTaskResolvingRepositoryByName() throws {
    let store = try temporaryStore()
    let repository = try store.createRepository(name: "operator", path: "/tmp/operator", defaultBranch: "main")
    let commands = OperatorCLICommands(store: store)

    let task = try commands.addTask(
        repository: "operator",
        title: "File follow-up",
        prompt: "Do the thing",
        effort: .high
    )

    #expect(task.repositoryID == repository.id.uuidString)
    #expect(task.status == "ready")
    #expect(task.reasoningEffort == "high")
    #expect(try store.tasks().count == 1)
}

@Test func taskAddResolvesRepositoryByID() throws {
    let store = try temporaryStore()
    let repository = try store.createRepository(name: "operator", path: "/tmp/operator", defaultBranch: "main")
    let commands = OperatorCLICommands(store: store)

    let task = try commands.addTask(
        repository: repository.id.uuidString.lowercased(),
        title: "By id",
        prompt: "Prompt",
        effort: .medium
    )

    #expect(task.repositoryID == repository.id.uuidString)
}

@Test func taskAddFailsWithNotFoundForUnknownRepository() throws {
    let store = try temporaryStore()
    let commands = OperatorCLICommands(store: store)

    #expect(throws: OperatorCLIError.repositoryNotFound("nope")) {
        try commands.addTask(repository: "nope", title: "T", prompt: "P", effort: .medium)
    }
}

@Test func taskAddFailsWhenRepositoryNameIsAmbiguous() throws {
    let store = try temporaryStore()
    _ = try store.createRepository(name: "dup", path: "/tmp/dup-one", defaultBranch: "main")
    _ = try store.createRepository(name: "dup", path: "/tmp/dup-two", defaultBranch: "main")
    let commands = OperatorCLICommands(store: store)

    #expect(throws: OperatorCLIError.ambiguousRepositoryName("dup")) {
        try commands.addTask(repository: "dup", title: "T", prompt: "P", effort: .medium)
    }
}

// MARK: - task list / show

@Test func taskListFiltersByRepositoryAndStatus() throws {
    let store = try temporaryStore()
    let repoA = try store.createRepository(name: "a", path: "/tmp/a", defaultBranch: "main")
    let repoB = try store.createRepository(name: "b", path: "/tmp/b", defaultBranch: "main")
    let readyA = try store.createTask(repositoryID: repoA.id, title: "Ready A", prompt: "P")
    let archivedA = try store.createTask(repositoryID: repoA.id, title: "Archived A", prompt: "P")
    _ = try store.archiveTask(id: archivedA.id)
    _ = try store.createTask(repositoryID: repoB.id, title: "Ready B", prompt: "P")
    let commands = OperatorCLICommands(store: store)

    let allTasks = try commands.listTasks(repository: nil, status: nil)
    let repoATasks = try commands.listTasks(repository: "a", status: nil)
    let readyRepoATasks = try commands.listTasks(repository: "a", status: .ready)

    #expect(allTasks.count == 3)
    #expect(repoATasks.count == 2)
    #expect(readyRepoATasks.map(\.id) == [readyA.id.uuidString])
}

@Test func taskShowReturnsTaskAndFailsForUnknownID() throws {
    let store = try temporaryStore()
    let repository = try store.createRepository(name: "operator", path: "/tmp/operator", defaultBranch: "main")
    let task = try store.createTask(repositoryID: repository.id, title: "Show me", prompt: "P")
    let commands = OperatorCLICommands(store: store)

    let shown = try commands.showTask(id: task.id.uuidString)
    #expect(shown.title == "Show me")

    let unknownID = UUID().uuidString
    #expect(throws: OperatorCLIError.taskNotFound(unknownID)) {
        try commands.showTask(id: unknownID)
    }
    #expect(throws: OperatorCLIError.taskNotFound("not-a-uuid")) {
        try commands.showTask(id: "not-a-uuid")
    }
}

// MARK: - task archive

@Test func taskArchiveArchivesAndRejectsDoubleArchive() throws {
    let store = try temporaryStore()
    let repository = try store.createRepository(name: "operator", path: "/tmp/operator", defaultBranch: "main")
    let task = try store.createTask(repositoryID: repository.id, title: "Archive", prompt: "P")
    let commands = OperatorCLICommands(store: store)

    let archived = try commands.archiveTask(id: task.id.uuidString)
    #expect(archived.status == "archived")

    #expect(throws: TaskLifecycleError.transitionNotAllowed) {
        try commands.archiveTask(id: task.id.uuidString)
    }
}

// MARK: - run list

@Test func runListReturnsRunsForTask() throws {
    let store = try temporaryStore()
    let repository = try store.createRepository(name: "operator", path: "/tmp/operator", defaultBranch: "main")
    let task = try store.createTask(repositoryID: repository.id, title: "Runs", prompt: "P")
    _ = try store.recordFailedRun(
        taskID: task.id,
        worktreePath: "/tmp/wt-failed",
        baseBranch: "main",
        baseRef: "abc",
        errorMessage: "boom"
    )
    let commands = OperatorCLICommands(store: store)

    let runs = try commands.listRuns(taskID: task.id.uuidString)

    #expect(runs.count == 1)
    #expect(runs.first?.status == "triggerFailed")
    #expect(runs.first?.errorMessage == "boom")
}

// MARK: - task send

@Test func sendWaitsUntilTheRunCompletes() async throws {
    let store = try temporaryStore()
    let repository = try store.createRepository(name: "operator", path: "/tmp/operator", defaultBranch: "main")
    let task = try store.createTask(repositoryID: repository.id, title: "Send", prompt: "P")
    let commands = OperatorCLICommands(store: store)
    let sender = FakeSender(store: store, outcome: .runningThenComplete(after: 0.3))

    let run = try await commands.sendTask(
        id: task.id.uuidString,
        using: sender,
        timeout: 5,
        pollInterval: 0.05
    )

    #expect(run.status == "triggered")
    #expect(try store.task(id: task.id)?.status == .done)
}

@Test func sendFailsWithSendFailedWhenTriggerFails() async throws {
    let store = try temporaryStore()
    let repository = try store.createRepository(name: "operator", path: "/tmp/operator", defaultBranch: "main")
    let task = try store.createTask(repositoryID: repository.id, title: "Send", prompt: "P")
    let commands = OperatorCLICommands(store: store)
    let sender = FakeSender(store: store, outcome: .failed("app-server rejected turn"))

    await #expect(throws: OperatorCLIError.sendFailed(message: "app-server rejected turn")) {
        _ = try await commands.sendTask(id: task.id.uuidString, using: sender, timeout: 5, pollInterval: 0.05)
    }
}

@Test func sendTimesOutWhenTheTurnNeverCompletes() async throws {
    let store = try temporaryStore()
    let repository = try store.createRepository(name: "operator", path: "/tmp/operator", defaultBranch: "main")
    let task = try store.createTask(repositoryID: repository.id, title: "Send", prompt: "P")
    let commands = OperatorCLICommands(store: store)
    let sender = FakeSender(store: store, outcome: .runningForever)

    await #expect(throws: OperatorCLIError.sendTimedOut(taskID: task.id.uuidString)) {
        _ = try await commands.sendTask(id: task.id.uuidString, using: sender, timeout: 0.2, pollInterval: 0.05)
    }
}

@Test func sendTimeoutFailsTheRunAndReturnsTheTaskToReadyForRetry() async throws {
    let store = try temporaryStore()
    let repository = try store.createRepository(name: "operator", path: "/tmp/operator", defaultBranch: "main")
    let task = try store.createTask(repositoryID: repository.id, title: "Send", prompt: "P")
    let commands = OperatorCLICommands(store: store)
    let sender = FakeSender(store: store, outcome: .runningForever)

    _ = try? await commands.sendTask(id: task.id.uuidString, using: sender, timeout: 0.2, pollInterval: 0.05)

    // Exiting on timeout kills the spawned app-server, so the turn is dead:
    // the run must not stay `running` (recovery would mark the task Done) and
    // the task must be sendable again.
    let run = try #require(try store.runs(taskID: task.id).first)
    #expect(run.status == .triggerFailed)
    #expect(run.errorMessage?.isEmpty == false)
    #expect(run.completedAt != nil)
    #expect(try store.task(id: task.id)?.status == .ready)

    let retried = try await commands.sendTask(
        id: task.id.uuidString,
        using: FakeSender(store: store, outcome: .runningThenComplete(after: 0.1)),
        timeout: 5,
        pollInterval: 0.05
    )
    #expect(retried.status == "triggered")
}

// MARK: - JSON output

@Test func taskJSONUsesTheDocumentedStableSchema() throws {
    let store = try temporaryStore()
    let repository = try store.createRepository(name: "operator", path: "/tmp/operator", defaultBranch: "main")
    _ = try store.createTask(repositoryID: repository.id, title: "JSON", prompt: "P")
    let commands = OperatorCLICommands(store: store)
    let task = try #require(try commands.listTasks(repository: nil, status: nil).first)

    let json = try CLIJSONOutput.encode(task)
    let object = try #require(
        try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
    )

    let expectedKeys: Set<String> = [
        "id", "repositoryID", "title", "prompt", "reasoningEffort",
        "status", "createdAt", "updatedAt"
    ]
    #expect(Set(object.keys) == expectedKeys)
    let createdAt = try #require(object["createdAt"] as? String)
    #expect(ISO8601DateFormatter().date(from: createdAt) != nil)
}

@Test func runJSONUsesTheDocumentedStableSchema() throws {
    let store = try temporaryStore()
    let repository = try store.createRepository(name: "operator", path: "/tmp/operator", defaultBranch: "main")
    let task = try store.createTask(repositoryID: repository.id, title: "JSON", prompt: "P")
    _ = try store.recordFailedRun(
        taskID: task.id,
        worktreePath: "/tmp/wt",
        baseBranch: "main",
        baseRef: "abc",
        errorMessage: "boom"
    )
    let commands = OperatorCLICommands(store: store)
    let run = try #require(try commands.listRuns(taskID: task.id.uuidString).first)

    let json = try CLIJSONOutput.encode(run)
    let object = try #require(
        try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
    )

    let expectedKeys: Set<String> = [
        "id", "taskID", "repositoryID", "status", "worktreePath", "baseBranch",
        "baseRef", "codexThreadID", "codexThreadURL", "errorMessage",
        "createdAt", "completedAt"
    ]
    // Optional nil fields are emitted as JSON null so the key set is stable.
    #expect(Set(object.keys) == expectedKeys)
}

// MARK: - error contract

@Test func failuresMapToTheDocumentedExitCodesAndCodes() {
    let notFound = cliFailure(for: OperatorCLIError.taskNotFound("x"))
    #expect(notFound.exitCode == 2)
    #expect(notFound.code == "notFound")

    let repoNotFound = cliFailure(for: OperatorCLIError.repositoryNotFound("x"))
    #expect(repoNotFound.exitCode == 2)
    #expect(repoNotFound.code == "notFound")

    let ambiguous = cliFailure(for: OperatorCLIError.ambiguousRepositoryName("dup"))
    #expect(ambiguous.exitCode == 2)
    #expect(ambiguous.code == "notFound")

    let storeNotFound = cliFailure(for: OperatorStoreError.taskNotFound)
    #expect(storeNotFound.exitCode == 2)
    #expect(storeNotFound.code == "notFound")

    let lifecycle = cliFailure(for: TaskLifecycleError.taskIsImmutable)
    #expect(lifecycle.exitCode == 3)
    #expect(lifecycle.code == "lifecycleViolation")

    let codexMissing = cliFailure(for: CodexBinaryConfigurationError.notFound)
    #expect(codexMissing.exitCode == 4)
    #expect(codexMissing.code == "codexUnavailable")

    let worktreeFailed = cliFailure(for: WorktreePreparationError.unableToCreateWorktree)
    #expect(worktreeFailed.exitCode == 5)
    #expect(worktreeFailed.code == "sendFailed")

    let sendFailed = cliFailure(for: OperatorCLIError.sendFailed(message: "boom"))
    #expect(sendFailed.exitCode == 5)
    #expect(sendFailed.code == "sendFailed")
    #expect(sendFailed.message.contains("boom"))

    let timeout = cliFailure(for: OperatorCLIError.sendTimedOut(taskID: "t"))
    #expect(timeout.exitCode == 6)
    #expect(timeout.code == "timeout")

    struct Mystery: Error {}
    let unexpected = cliFailure(for: Mystery())
    #expect(unexpected.exitCode == 70)
    #expect(unexpected.code == "internal")
}

@Test func jsonErrorPayloadUsesTheDocumentedShape() throws {
    let failure = cliFailure(for: OperatorCLIError.taskNotFound("x"))

    let json = try CLIJSONOutput.encodeError(failure)
    let object = try #require(
        try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
    )
    let error = try #require(object["error"] as? [String: Any])

    #expect(error["code"] as? String == "notFound")
    #expect((error["message"] as? String)?.isEmpty == false)
}

// MARK: - helpers

private func temporaryStore() throws -> OperatorStore {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "OperatorCLICoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return try OperatorStore(databaseURL: directory.appending(path: "operator.sqlite"))
}

private struct FakeSender: CodexTaskSending {
    enum Outcome {
        case failed(String)
        case runningThenComplete(after: TimeInterval)
        case runningForever
    }

    let store: OperatorStore
    let outcome: Outcome

    func sendTaskToCodex(taskID: UUID) async throws -> OperatorRun {
        switch outcome {
        case .failed(let message):
            return try store.recordFailedRun(
                taskID: taskID,
                worktreePath: "/tmp/wt",
                baseBranch: "main",
                baseRef: "abc",
                errorMessage: message
            )
        case .runningThenComplete(let delay):
            let run = try startedRun(taskID: taskID)
            let store = store
            Task {
                try? await Task.sleep(for: .seconds(delay))
                _ = try? store.completeStartedRun(id: run.id)
            }
            return run
        case .runningForever:
            return try startedRun(taskID: taskID)
        }
    }

    private func startedRun(taskID: UUID) throws -> OperatorRun {
        try store.recordStartedRun(
            taskID: taskID,
            worktreePath: "/tmp/wt",
            baseBranch: "main",
            baseRef: "abc",
            codexThreadID: "thread-1",
            codexThreadURL: nil
        )
    }
}

// MARK: - database override

@Test func databaseURLOverrideReadsTheOperatorDBVariable() {
    let url = OperatorCLIEnvironment.databaseURLOverride(
        environment: ["OPERATOR_DB": "/tmp/override.sqlite"]
    )
    #expect(url == URL(filePath: "/tmp/override.sqlite"))

    #expect(OperatorCLIEnvironment.databaseURLOverride(environment: [:]) == nil)
}

@Test func sendLocationsFollowTheDataDirectoryOverride() throws {
    // A sandboxed send (OPERATOR_DB pointing at a scratch database) must not
    // run git operations against the production worktree root, so the data
    // directory override relocates every path `task send` writes to.
    let locations = try OperatorCLIEnvironment.sendLocations(
        environment: ["OPERATOR_DATA_DIR": "/tmp/sandbox"]
    )
    #expect(locations.appDataURL == URL(filePath: "/tmp/sandbox", directoryHint: .isDirectory))
    #expect(
        locations.worktreeRootURL
            == URL(filePath: "/tmp/sandbox", directoryHint: .isDirectory)
                .appending(path: "worktrees", directoryHint: .isDirectory)
    )
}

@Test func sendLocationsDefaultToTheProductionPathsWithoutOverride() throws {
    let locations = try OperatorCLIEnvironment.sendLocations(environment: [:])
    #expect(locations.appDataURL == (try OperatorAppBootstrap.applicationDataURL()))
    #expect(locations.worktreeRootURL == OperatorAppBootstrap.codexWorktreesURL())
}

// MARK: - repo add

@Test func repoAddRegistersARepositoryUsingTheInspector() throws {
    let store = try temporaryStore()
    let commands = OperatorCLICommands(
        store: store,
        repositoryInspector: FakeInspector(result: .success(RepositoryInspection(
            name: "operator",
            path: "/tmp/operator-root",
            defaultBranch: "main"
        )))
    )

    let repository = try commands.addRepository(path: "/tmp/operator-root/subdir")

    #expect(repository.name == "operator")
    #expect(repository.path == "/tmp/operator-root")
    #expect(repository.defaultBranch == "main")
    #expect(try store.repositories().count == 1)
}

@Test func repoAddFailsForANonGitPath() throws {
    let store = try temporaryStore()
    let commands = OperatorCLICommands(
        store: store,
        repositoryInspector: FakeInspector(
            result: .failure(RepositoryRegistrationError.invalidGitRepository(path: "/tmp/nope"))
        )
    )

    #expect(throws: RepositoryRegistrationError.invalidGitRepository(path: "/tmp/nope")) {
        try commands.addRepository(path: "/tmp/nope")
    }
    #expect(try store.repositories().isEmpty)
}

@Test func repoAddFailuresMapToTheDocumentedExitCodes() throws {
    let invalid = cliFailure(for: RepositoryRegistrationError.invalidGitRepository(path: "/tmp/nope"))
    #expect(invalid.exitCode == 7)
    #expect(invalid.code == "invalidRepository")

    let gitFailed = cliFailure(for: RepositoryRegistrationError.gitCommandFailed)
    #expect(gitFailed.exitCode == 7)
    #expect(gitFailed.code == "invalidRepository")

    let existingID = UUID()
    let duplicate = cliFailure(
        for: OperatorStoreError.repositoryPathAlreadyRegistered(existingID: existingID)
    )
    #expect(duplicate.exitCode == 8)
    #expect(duplicate.code == "alreadyRegistered")
    #expect(duplicate.message.contains(existingID.uuidString))
}

private struct FakeInspector: RepositoryInspecting {
    let result: Result<RepositoryInspection, RepositoryRegistrationError>

    func inspect(_ repositoryURL: URL) throws -> RepositoryInspection {
        try result.get()
    }
}
