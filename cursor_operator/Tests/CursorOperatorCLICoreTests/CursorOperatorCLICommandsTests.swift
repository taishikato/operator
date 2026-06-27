import Foundation
import Testing
import CursorOperatorCore
@testable import CursorOperatorCLICore

// MARK: - repo list/add

@Test func repoListReturnsRegisteredRepositories() throws {
    let store = try temporaryStore()
    let repository = try store.createRepository(
        name: "operator",
        localPath: "/tmp/operator",
        githubURL: URL(string: "https://github.com/example/operator")!,
        defaultBranch: "main"
    )
    let commands = CursorOperatorCLICommands(store: store)

    let repositories = try commands.listRepositories()

    #expect(repositories.map(\.id) == [repository.id.uuidString])
    #expect(repositories.first?.name == "operator")
    #expect(repositories.first?.githubURL == "https://github.com/example/operator")
    #expect(repositories.first?.defaultBranch == "main")
}

@Test func repoAddRegistersARepositoryUsingTheInspector() throws {
    let store = try temporaryStore()
    let commands = CursorOperatorCLICommands(
        store: store,
        repositoryInspector: FakeInspector(result: .success(CursorRepositoryInspection(
            name: "operator",
            localPath: "/tmp/operator-root",
            githubURL: URL(string: "https://github.com/example/operator")!,
            defaultBranch: "main"
        )))
    )

    let repository = try commands.addRepository(path: "/tmp/operator-root/subdir")

    #expect(repository.name == "operator")
    #expect(repository.localPath == "/tmp/operator-root")
    #expect(repository.githubURL == "https://github.com/example/operator")
    #expect(try store.repositories().count == 1)
}

// MARK: - task add/list/show/archive

@Test func taskAddCreatesReadyTaskResolvingRepositoryByName() throws {
    let store = try temporaryStore()
    let repository = try makeRepository(in: store, name: "operator")
    let commands = CursorOperatorCLICommands(store: store)

    let task = try commands.addTask(
        repository: "operator",
        title: "File follow-up",
        prompt: "Do the thing",
        autoCreatePR: true
    )

    #expect(task.repositoryID == repository.id.uuidString)
    #expect(task.status == "ready")
    #expect(task.autoCreatePR == true)
    #expect(task.reasoningEffort == "medium")
    #expect(task.useFastModel == false)
    #expect(task.harness == "cursor")
    #expect(try store.tasks().count == 1)
}

@Test func taskAddCanAutoSendCreatedTask() async throws {
    let store = try temporaryStore()
    _ = try makeRepository(in: store, name: "operator")
    let runtime = FakeRuntime(startResult: .success(CursorCloudAgentReference(
        agentID: "agent-auto-send",
        runID: "run-auto-send",
        openURL: URL(string: "https://cursor.com/agents/agent-auto-send")!
    )))
    let commands = CursorOperatorCLICommands(
        store: store,
        credentialProvider: CursorCredentialProvider(store: InMemoryCursorCredentialStore(apiKey: "crsr_test")),
        runtime: runtime
    )

    let result = try await commands.addTask(
        repository: "operator",
        title: "Auto send",
        prompt: "Do the thing",
        autoCreatePR: true,
        autoSend: true
    )

    #expect(result.task.title == "Auto send")
    #expect(result.task.status == "running")
    #expect(result.runAttempt?.status == "succeeded")
    #expect(result.runAttempt?.cursorRunID == "run-auto-send")
    #expect(try store.tasks().first?.status == .running)
    #expect(runtime.requests.count == 1)
    #expect(runtime.requests.first?.autoCreatePR == true)
}

@Test func taskAddTrimsTitleAndPreservesPromptBeforeCreatingTask() throws {
    let store = try temporaryStore()
    _ = try makeRepository(in: store, name: "operator")
    let commands = CursorOperatorCLICommands(store: store)

    let task = try commands.addTask(
        repository: "operator",
        title: "  File follow-up  ",
        prompt: "\nDo the thing\t",
        autoCreatePR: false
    )

    #expect(task.title == "File follow-up")
    #expect(task.prompt == "\nDo the thing\t")
}

@Test func taskAddRejectsBlankTitleAndPrompt() throws {
    let store = try temporaryStore()
    _ = try makeRepository(in: store, name: "operator")
    let commands = CursorOperatorCLICommands(store: store)

    #expect(throws: CursorTaskCreationError.titleRequired) {
        try commands.addTask(repository: "operator", title: " \n\t", prompt: "Prompt", autoCreatePR: false)
    }
    #expect(throws: CursorTaskCreationError.promptRequired) {
        try commands.addTask(repository: "operator", title: "Title", prompt: " \n\t", autoCreatePR: false)
    }
}

@Test func taskAddResolvesRepositoryByIDAndRejectsAmbiguousNames() throws {
    let store = try temporaryStore()
    let repository = try makeRepository(in: store, name: "operator", path: "/tmp/operator")
    _ = try makeRepository(in: store, name: "dup", path: "/tmp/dup-one")
    _ = try makeRepository(in: store, name: "dup", path: "/tmp/dup-two")
    let commands = CursorOperatorCLICommands(store: store)

    let task = try commands.addTask(
        repository: repository.id.uuidString.lowercased(),
        title: "By id",
        prompt: "Prompt",
        autoCreatePR: false
    )
    #expect(task.repositoryID == repository.id.uuidString)

    #expect(throws: CursorOperatorCLIError.ambiguousRepositoryName("dup")) {
        try commands.addTask(repository: "dup", title: "T", prompt: "P", autoCreatePR: false)
    }
}

@Test func taskListFiltersByRepositoryAndStatus() throws {
    let store = try temporaryStore()
    let repoA = try makeRepository(in: store, name: "a", path: "/tmp/a")
    let repoB = try makeRepository(in: store, name: "b", path: "/tmp/b")
    let readyA = try store.createTask(repositoryID: repoA.id, title: "Ready A", prompt: "P")
    let archivedA = try store.createTask(repositoryID: repoA.id, title: "Archived A", prompt: "P")
    _ = try store.archiveTask(id: archivedA.id)
    _ = try store.createTask(repositoryID: repoB.id, title: "Ready B", prompt: "P")
    let commands = CursorOperatorCLICommands(store: store)

    let allTasks = try commands.listTasks(repository: nil, status: nil)
    let repoATasks = try commands.listTasks(repository: "a", status: nil)
    let readyRepoATasks = try commands.listTasks(repository: "a", status: .ready)

    #expect(allTasks.count == 3)
    #expect(repoATasks.count == 2)
    #expect(readyRepoATasks.map(\.id) == [readyA.id.uuidString])
}

@Test func taskShowAndArchiveUseTaskIDs() throws {
    let store = try temporaryStore()
    let repository = try makeRepository(in: store, name: "operator")
    let task = try store.createTask(repositoryID: repository.id, title: "Show me", prompt: "P")
    let commands = CursorOperatorCLICommands(store: store)

    let shown = try commands.showTask(id: task.id.uuidString)
    #expect(shown.title == "Show me")

    let archived = try commands.archiveTask(id: task.id.uuidString)
    #expect(archived.status == "archived")

    let unknownID = UUID().uuidString
    #expect(throws: CursorOperatorCLIError.taskNotFound(unknownID)) {
        try commands.showTask(id: unknownID)
    }
}

// MARK: - run list/send

@Test func runListReturnsAttemptsForTaskWithStableNullFields() throws {
    let store = try temporaryStore()
    let repository = try makeRepository(in: store, name: "operator")
    let task = try store.createTask(repositoryID: repository.id, title: "Runs", prompt: "P")
    _ = try store.recordFailedSendAttempt(
        taskID: task.id,
        repositoryURL: repository.githubURL,
        startingRef: repository.defaultBranch,
        model: CursorModel.fixed,
        autoCreatePR: false,
        prompt: task.prompt,
        errorMessage: "boom"
    )
    let commands = CursorOperatorCLICommands(store: store)

    let attempts = try commands.listRuns(taskID: task.id.uuidString)

    #expect(attempts.count == 1)
    #expect(attempts.first?.status == "failed")
    #expect(attempts.first?.errorMessage == "boom")

    let json = try CursorCLIJSONOutput.encode(try #require(attempts.first))
    let object = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    #expect(Set(object.keys) == [
        "id", "taskID", "repositoryID", "status", "repositoryURL", "startingRef",
        "model", "autoCreatePR", "prompt", "cursorAgentID", "cursorRunID",
        "cursorURL", "errorMessage", "createdAt", "completedAt"
    ])
}

@Test func sendStartsCursorRunAndCanWaitForCompletion() async throws {
    let store = try temporaryStore()
    let repository = try makeRepository(in: store, name: "operator")
    let task = try store.createTask(repositoryID: repository.id, title: "Send", prompt: "P")
    let runtime = FakeRuntime(startResult: .success(CursorCloudAgentReference(
        agentID: "agent-123",
        runID: "run-123",
        openURL: URL(string: "https://cursor.com/agents/agent-123")!
    )), waitResult: CursorCloudAgentRunCompletion(status: "finished", result: nil))
    let commands = CursorOperatorCLICommands(
        store: store,
        credentialProvider: CursorCredentialProvider(store: InMemoryCursorCredentialStore(apiKey: "crsr_test")),
        runtime: runtime
    )

    let attempt = try await commands.sendTask(id: task.id.uuidString, wait: true)

    #expect(attempt.status == "succeeded")
    #expect(attempt.cursorAgentID == "agent-123")
    #expect(attempt.cursorRunID == "run-123")
    #expect(try store.task(id: task.id)?.status == .done)
    #expect(runtime.waitedReferences.map(\.runID) == ["run-123"])
}

@Test func sendWaitFailsWhenCursorRunIsStillRunning() async throws {
    let store = try temporaryStore()
    let repository = try makeRepository(in: store, name: "operator")
    let task = try store.createTask(repositoryID: repository.id, title: "Send", prompt: "P")
    let runtime = FakeRuntime(startResult: .success(CursorCloudAgentReference(
        agentID: "agent-123",
        runID: "run-123",
        openURL: URL(string: "https://cursor.com/agents/agent-123")!
    )), waitResult: CursorCloudAgentRunCompletion(status: "running", result: nil))
    let commands = CursorOperatorCLICommands(
        store: store,
        credentialProvider: CursorCredentialProvider(store: InMemoryCursorCredentialStore(apiKey: "crsr_test")),
        runtime: runtime
    )

    await #expect(throws: CursorOperatorCLIError.sendFailed(message: "Cursor run is still running.")) {
        _ = try await commands.sendTask(id: task.id.uuidString, wait: true)
    }
    #expect(try store.task(id: task.id)?.status == .running)
}

@Test func sendFailureIsReturnedForCursorRuntimeFailuresAndTaskStaysReady() async throws {
    let store = try temporaryStore()
    let repository = try makeRepository(in: store, name: "operator")
    let task = try store.createTask(repositoryID: repository.id, title: "Send", prompt: "P")
    let commands = CursorOperatorCLICommands(
        store: store,
        credentialProvider: CursorCredentialProvider(store: InMemoryCursorCredentialStore(apiKey: "crsr_test")),
        runtime: FakeRuntime(startResult: .failure(CursorRuntimeFailure(message: "Cursor rejected the request.")))
    )

    await #expect(throws: CursorOperatorCLIError.sendFailed(message: "Cursor rejected the request.")) {
        _ = try await commands.sendTask(id: task.id.uuidString, wait: false)
    }

    #expect(try store.task(id: task.id)?.status == .ready)
}

@Test func failuresMapToTheDocumentedExitCodesAndCodes() {
    let notFound = cursorCLIFailure(for: CursorOperatorCLIError.taskNotFound("x"))
    #expect(notFound.exitCode == 2)
    #expect(notFound.code == "notFound")

    let lifecycle = cursorCLIFailure(for: CursorTaskLifecycleError.taskIsImmutable)
    #expect(lifecycle.exitCode == 3)
    #expect(lifecycle.code == "lifecycleViolation")

    let missingCredential = cursorCLIFailure(for: CursorTaskSendError.missingCredentials)
    #expect(missingCredential.exitCode == 4)
    #expect(missingCredential.code == "cursorUnavailable")

    let sendFailed = cursorCLIFailure(for: CursorOperatorCLIError.sendFailed(message: "boom"))
    #expect(sendFailed.exitCode == 5)
    #expect(sendFailed.code == "sendFailed")

    let startedButNotRecorded = cursorCLIFailure(for: CursorTaskSendError.startedRunCouldNotBeRecorded(
        CursorCloudAgentReference(
            agentID: "agent-1",
            runID: "run-1",
            openURL: URL(string: "https://cursor.com/agents/agent-1")!
        )
    ))
    #expect(startedButNotRecorded.exitCode == 5)
    #expect(startedButNotRecorded.code == "sendFailed")

    let invalidRepository = cursorCLIFailure(for: CursorRepositoryRegistrationError.invalidGitRepository(path: "/tmp/nope"))
    #expect(invalidRepository.exitCode == 7)
    #expect(invalidRepository.code == "invalidRepository")
}

@Test func databaseURLOverrideReadsCursorSpecificVariable() {
    let url = CursorOperatorCLIEnvironment.databaseURLOverride(
        environment: ["CURSOR_OPERATOR_DB": "/tmp/cursor.sqlite"]
    )

    #expect(url == URL(filePath: "/tmp/cursor.sqlite"))
    #expect(CursorOperatorCLIEnvironment.databaseURLOverride(environment: [:]) == nil)
}

// MARK: - helpers

private func temporaryStore() throws -> CursorOperatorStore {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "CursorOperatorCLICoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return try CursorOperatorStore(databaseURL: directory.appending(path: "operator.sqlite"))
}

private func makeRepository(
    in store: CursorOperatorStore,
    name: String,
    path: String = "/tmp/operator"
) throws -> CursorRepository {
    try store.createRepository(
        name: name,
        localPath: path,
        githubURL: URL(string: "https://github.com/example/\(name)")!,
        defaultBranch: "main"
    )
}

private struct FakeInspector: CursorRepositoryInspecting {
    let result: Result<CursorRepositoryInspection, Error>

    func inspect(_ repositoryURL: URL) throws -> CursorRepositoryInspection {
        try result.get()
    }
}

private final class FakeRuntime: CursorCloudAgentRuntime, @unchecked Sendable {
    var startResult: Result<CursorCloudAgentReference, CursorRuntimeFailure>
    var waitResult: CursorCloudAgentRunCompletion
    private(set) var requests: [CursorCloudAgentRequestPreview] = []
    private(set) var waitedReferences: [CursorCloudAgentReference] = []

    init(
        startResult: Result<CursorCloudAgentReference, CursorRuntimeFailure>,
        waitResult: CursorCloudAgentRunCompletion = CursorCloudAgentRunCompletion(status: "running", result: nil)
    ) {
        self.startResult = startResult
        self.waitResult = waitResult
    }

    func startCloudAgent(request: CursorCloudAgentRequestPreview, apiKey: String) async throws -> CursorCloudAgentReference {
        requests.append(request)
        return try startResult.get()
    }

    func waitForRun(reference: CursorCloudAgentReference, apiKey: String) async throws -> CursorCloudAgentRunCompletion {
        waitedReferences.append(reference)
        return waitResult
    }
}
