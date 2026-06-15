import Foundation
import Testing
@testable import OperatorDesktop

@Test func codexTriggerPreparesWorktreeStartsThreadAndRecordsSuccessfulRun() async throws {
    let store = try OperatorStore(databaseURL: temporaryDatabaseURL())
    let repository = try store.createRepository(name: "operator", path: "/tmp/operator", defaultBranch: "main")
    let task = try store.createTask(
        repositoryID: repository.id,
        title: "Exact prompt",
        prompt: "Implement this exactly.\nDo not add metadata.",
        reasoningEffort: .high
    )
    let worktreeURL = URL(filePath: "/tmp/operator-worktree-1")
    let worktreePreparer = FakeCodexWorktreePreparer(preparedWorktrees: [
        PreparedWorktree(
            worktreeURL: worktreeURL,
            baseBranch: "main",
            baseRef: "abc123",
            gitOriginURL: "git@github.com:taishikato/operator.git"
        )
    ])
    let appServer = FakeCodexAppServerClient(results: [
        .success(startedThread(id: "thread-1", url: URL(string: "codex://threads/thread-1")))
    ])
    let service = CodexTriggerService(
        store: store,
        worktreePreparer: worktreePreparer,
        appServerClient: appServer
    )

    let run = try await service.sendTaskToCodex(taskID: task.id)

    #expect(run.status == .running)
    #expect(run.worktreePath == worktreeURL.path)
    #expect(run.baseBranch == "main")
    #expect(run.baseRef == "abc123")
    #expect(run.codexThreadID == "thread-1")
    #expect(run.codexThreadURL == URL(string: "codex://threads/thread-1"))
    #expect(try store.task(id: task.id)?.status == .review)
    #expect(try store.runs(taskID: task.id).map(\.id) == [run.id])
    #expect(worktreePreparer.repositories.map(\.id) == [repository.id])
    #expect(appServer.requests == [
        CodexThreadStartRequest(
            cwd: worktreeURL,
            gitInfo: CodexThreadGitInfo(
                sha: "abc123",
                branch: "main",
                originURL: "git@github.com:taishikato/operator.git"
            ),
            model: "gpt-5.5",
            reasoningEffort: .high,
            prompt: "Implement this exactly.\nDo not add metadata.",
            displayName: "Exact prompt"
        )
    ])
}

@Test func codexTriggerMarksStartedRunTriggeredAfterTurnCompletion() async throws {
    let store = try OperatorStore(databaseURL: temporaryDatabaseURL())
    let repository = try store.createRepository(name: "operator", path: "/tmp/operator", defaultBranch: "main")
    let task = try store.createTask(repositoryID: repository.id, title: "Wait for turn", prompt: "Prompt")
    let worktreeURL = URL(filePath: "/tmp/operator-worktree-running")
    let worktreePreparer = FakeCodexWorktreePreparer(preparedWorktrees: [
        PreparedWorktree(worktreeURL: worktreeURL, baseBranch: "main", baseRef: "abc123")
    ])
    let turnCompletion = CodexTurnCompletionSignal()
    let appServer = FakeCodexAppServerClient(results: [
        .success(CodexStartedThread(
            reference: CodexThreadReference(id: "thread-running", url: URL(string: "codex://threads/thread-running")),
            turnCompletion: turnCompletion
        ))
    ])
    let service = CodexTriggerService(
        store: store,
        worktreePreparer: worktreePreparer,
        appServerClient: appServer
    )

    let run = try await service.sendTaskToCodex(taskID: task.id)

    #expect(run.status == .running)
    #expect(run.completedAt == nil)
    #expect(try store.runs(taskID: task.id).map(\.status) == [.running])

    await turnCompletion.complete()
    await waitUntil {
        ((try? store.runs(taskID: task.id).first?.status) ?? nil) == .triggered
    }

    let completedRun = try #require(store.runs(taskID: task.id).first)
    #expect(completedRun.id == run.id)
    #expect(completedRun.status == .triggered)
    #expect(completedRun.completedAt != nil)
}

@Test func codexTriggerHidesThreadWhileRunningAndRevealsBeforeCompletingRun() async throws {
    let store = try OperatorStore(databaseURL: temporaryDatabaseURL())
    let repository = try store.createRepository(name: "operator", path: "/tmp/operator", defaultBranch: "main")
    let task = try store.createTask(repositoryID: repository.id, title: "Hidden while running", prompt: "Prompt")
    let worktreePreparer = FakeCodexWorktreePreparer(preparedWorktrees: [
        PreparedWorktree(worktreeURL: URL(filePath: "/tmp/operator-worktree-hidden"), baseBranch: "main", baseRef: "abc123")
    ])
    let turnCompletion = CodexTurnCompletionSignal()
    let appServer = FakeCodexAppServerClient(results: [
        .success(CodexStartedThread(
            reference: CodexThreadReference(id: "thread-hidden", url: nil),
            turnCompletion: turnCompletion
        ))
    ])
    let visibility = FakeThreadVisibilityController()
    let taskID = task.id
    visibility.onReveal = { [store] _ in
        // The reveal must happen while the run is still recorded as running,
        // so the thread becomes visible before the task moves to Done.
        let status = (try? store.runs(taskID: taskID).first?.status) ?? nil
        visibility.recordRunStatusAtReveal(status)
    }
    let service = CodexTriggerService(
        store: store,
        worktreePreparer: worktreePreparer,
        appServerClient: appServer,
        threadVisibility: visibility
    )

    let run = try await service.sendTaskToCodex(taskID: task.id)

    #expect(run.status == .running)
    await waitUntil { visibility.hideCalls == ["thread-hidden"] }
    #expect(visibility.hideCalls == ["thread-hidden"])
    #expect(visibility.revealCalls.isEmpty)

    await turnCompletion.complete()
    await waitUntil {
        ((try? store.runs(taskID: taskID).first?.status) ?? nil) == .triggered
    }

    #expect(visibility.revealCalls == ["thread-hidden"])
    #expect(visibility.runStatusAtReveal == .running)
    #expect(try store.task(id: task.id)?.status == .done)
}

@Test func codexTriggerSkipsRevealWhenThreadWasNeverHidden() async throws {
    let store = try OperatorStore(databaseURL: temporaryDatabaseURL())
    let repository = try store.createRepository(name: "operator", path: "/tmp/operator", defaultBranch: "main")
    let task = try store.createTask(repositoryID: repository.id, title: "Never hidden", prompt: "Prompt")
    let worktreePreparer = FakeCodexWorktreePreparer(preparedWorktrees: [
        PreparedWorktree(worktreeURL: URL(filePath: "/tmp/operator-worktree-unhidden"), baseBranch: "main", baseRef: "abc123")
    ])
    let turnCompletion = CodexTurnCompletionSignal()
    let appServer = FakeCodexAppServerClient(results: [
        .success(CodexStartedThread(
            reference: CodexThreadReference(id: "thread-unhidden", url: nil),
            turnCompletion: turnCompletion
        ))
    ])
    let visibility = FakeThreadVisibilityController()
    visibility.hideResult = false
    let service = CodexTriggerService(
        store: store,
        worktreePreparer: worktreePreparer,
        appServerClient: appServer,
        threadVisibility: visibility
    )

    _ = try await service.sendTaskToCodex(taskID: task.id)
    await turnCompletion.complete()
    await waitUntil {
        ((try? store.runs(taskID: task.id).first?.status) ?? nil) == .triggered
    }

    #expect(visibility.hideCalls == ["thread-unhidden"])
    #expect(visibility.revealCalls.isEmpty)
}

@Test func codexTriggerRecoversInterruptedRunsByRevealingAndCompleting() async throws {
    let store = try OperatorStore(databaseURL: temporaryDatabaseURL())
    let repository = try store.createRepository(name: "operator", path: "/tmp/operator", defaultBranch: "main")
    let task = try store.createTask(repositoryID: repository.id, title: "Interrupted", prompt: "Prompt")
    let run = try store.recordStartedRun(
        taskID: task.id,
        worktreePath: "/tmp/operator-worktree-interrupted",
        baseBranch: "main",
        baseRef: "abc123",
        codexThreadID: "thread-interrupted",
        codexThreadURL: nil
    )
    let visibility = FakeThreadVisibilityController()
    let service = CodexTriggerService(
        store: store,
        worktreePreparer: FakeCodexWorktreePreparer(preparedWorktrees: []),
        appServerClient: FakeCodexAppServerClient(results: []),
        threadVisibility: visibility
    )

    await service.recoverInterruptedRuns()

    #expect(visibility.revealCalls == ["thread-interrupted"])
    #expect(try store.runs(taskID: task.id).first?.id == run.id)
    #expect(try store.runs(taskID: task.id).first?.status == .triggered)
    #expect(try store.task(id: task.id)?.status == .done)
}

@Test func codexTriggerRecoverySkipsRunningRunOwnedByLiveForeignProcess() async throws {
    let store = try OperatorStore(databaseURL: temporaryDatabaseURL())
    let repository = try store.createRepository(name: "operator", path: "/tmp/operator", defaultBranch: "main")
    let task = try store.createTask(repositoryID: repository.id, title: "CLI in flight", prompt: "Prompt")
    // A live process other than the test runner stands in for the operator
    // CLI that is still mid-send when the app launches.
    let foreignProcess = Process()
    foreignProcess.executableURL = URL(filePath: "/bin/sleep")
    foreignProcess.arguments = ["60"]
    try foreignProcess.run()
    defer {
        foreignProcess.terminate()
        foreignProcess.waitUntilExit()
    }
    let run = try store.recordStartedRun(
        taskID: task.id,
        worktreePath: "/tmp/operator-worktree-foreign",
        baseBranch: "main",
        baseRef: "abc123",
        codexThreadID: "thread-foreign",
        codexThreadURL: nil,
        ownerPID: foreignProcess.processIdentifier
    )
    let visibility = FakeThreadVisibilityController()
    let service = CodexTriggerService(
        store: store,
        worktreePreparer: FakeCodexWorktreePreparer(preparedWorktrees: []),
        appServerClient: FakeCodexAppServerClient(results: []),
        threadVisibility: visibility
    )

    await service.recoverInterruptedRuns()

    #expect(visibility.revealCalls.isEmpty)
    #expect(try store.runs(taskID: task.id).first?.id == run.id)
    #expect(try store.runs(taskID: task.id).first?.status == .running)
    #expect(try store.task(id: task.id)?.status == .review)
}

@Test func codexTriggerRecoveryCompletesRunningRunWhoseOwnerProcessDied() async throws {
    let store = try OperatorStore(databaseURL: temporaryDatabaseURL())
    let repository = try store.createRepository(name: "operator", path: "/tmp/operator", defaultBranch: "main")
    let task = try store.createTask(repositoryID: repository.id, title: "Owner died", prompt: "Prompt")
    // A reaped child gives a PID that is guaranteed dead.
    let deadProcess = Process()
    deadProcess.executableURL = URL(filePath: "/usr/bin/true")
    try deadProcess.run()
    deadProcess.waitUntilExit()
    let run = try store.recordStartedRun(
        taskID: task.id,
        worktreePath: "/tmp/operator-worktree-dead-owner",
        baseBranch: "main",
        baseRef: "abc123",
        codexThreadID: "thread-dead-owner",
        codexThreadURL: nil,
        ownerPID: deadProcess.processIdentifier
    )
    let visibility = FakeThreadVisibilityController()
    let service = CodexTriggerService(
        store: store,
        worktreePreparer: FakeCodexWorktreePreparer(preparedWorktrees: []),
        appServerClient: FakeCodexAppServerClient(results: []),
        threadVisibility: visibility
    )

    await service.recoverInterruptedRuns()

    #expect(visibility.revealCalls == ["thread-dead-owner"])
    #expect(try store.runs(taskID: task.id).first?.id == run.id)
    #expect(try store.runs(taskID: task.id).first?.status == .triggered)
    #expect(try store.task(id: task.id)?.status == .done)
}

@Test func codexTriggerRecoveryFailsCLIStartedRunWhoseOwnerProcessDied() async throws {
    let store = try OperatorStore(databaseURL: temporaryDatabaseURL())
    let repository = try store.createRepository(name: "operator", path: "/tmp/operator", defaultBranch: "main")
    let task = try store.createTask(repositoryID: repository.id, title: "CLI owner died", prompt: "Prompt")
    let deadProcess = Process()
    deadProcess.executableURL = URL(filePath: "/usr/bin/true")
    try deadProcess.run()
    deadProcess.waitUntilExit()
    let run = try store.recordStartedRun(
        taskID: task.id,
        worktreePath: "/tmp/operator-worktree-dead-cli-owner",
        baseBranch: "main",
        baseRef: "abc123",
        codexThreadID: "thread-dead-cli-owner",
        codexThreadURL: nil,
        ownerPID: deadProcess.processIdentifier,
        ownerKind: .cli
    )
    let visibility = FakeThreadVisibilityController()
    let service = CodexTriggerService(
        store: store,
        worktreePreparer: FakeCodexWorktreePreparer(preparedWorktrees: []),
        appServerClient: FakeCodexAppServerClient(results: []),
        threadVisibility: visibility
    )

    await service.recoverInterruptedRuns()

    #expect(visibility.revealCalls == ["thread-dead-cli-owner"])
    #expect(try store.runs(taskID: task.id).first?.id == run.id)
    #expect(try store.runs(taskID: task.id).first?.status == .triggerFailed)
    #expect(try store.task(id: task.id)?.status == .ready)
}

@Test func codexTriggerRecoveryCompletesRunningRunWithoutRecordedOwner() async throws {
    let store = try OperatorStore(databaseURL: temporaryDatabaseURL())
    let repository = try store.createRepository(name: "operator", path: "/tmp/operator", defaultBranch: "main")
    let task = try store.createTask(repositoryID: repository.id, title: "Legacy run", prompt: "Prompt")
    // Rows recorded before the ownerPID migration carry no owner.
    let run = try store.recordStartedRun(
        taskID: task.id,
        worktreePath: "/tmp/operator-worktree-legacy",
        baseBranch: "main",
        baseRef: "abc123",
        codexThreadID: "thread-legacy",
        codexThreadURL: nil,
        ownerPID: nil
    )
    let service = CodexTriggerService(
        store: store,
        worktreePreparer: FakeCodexWorktreePreparer(preparedWorktrees: []),
        appServerClient: FakeCodexAppServerClient(results: [])
    )

    await service.recoverInterruptedRuns()

    #expect(try store.runs(taskID: task.id).first?.id == run.id)
    #expect(try store.runs(taskID: task.id).first?.status == .triggered)
    #expect(try store.task(id: task.id)?.status == .done)
}

@Test func codexTriggerRecordsFailureAndRetryUsesFreshWorktreeAndRun() async throws {
    let store = try OperatorStore(databaseURL: temporaryDatabaseURL())
    let repository = try store.createRepository(name: "operator", path: "/tmp/operator", defaultBranch: "main")
    let task = try store.createTask(repositoryID: repository.id, title: "Retry", prompt: "Try once")
    let firstWorktreeURL = URL(filePath: "/tmp/operator-worktree-failed")
    let secondWorktreeURL = URL(filePath: "/tmp/operator-worktree-success")
    let worktreePreparer = FakeCodexWorktreePreparer(preparedWorktrees: [
        PreparedWorktree(worktreeURL: firstWorktreeURL, baseBranch: "main", baseRef: "abc123"),
        PreparedWorktree(worktreeURL: secondWorktreeURL, baseBranch: "main", baseRef: "def456")
    ])
    let appServer = FakeCodexAppServerClient(results: [
        .failure(FakeCodexAppServerError(message: String(repeating: "app-server rejected ", count: 20))),
        .success(startedThread(id: "thread-retry", url: nil))
    ])
    let service = CodexTriggerService(
        store: store,
        worktreePreparer: worktreePreparer,
        appServerClient: appServer
    )

    let failedRun = try await service.sendTaskToCodex(taskID: task.id)

    #expect(failedRun.status == .triggerFailed)
    #expect(failedRun.worktreePath == firstWorktreeURL.path)
    #expect(failedRun.errorMessage != nil)
    #expect((failedRun.errorMessage ?? "").count <= 160)
    #expect(try store.task(id: task.id)?.status == .ready)

    let successfulRun = try await service.sendTaskToCodex(taskID: task.id)

    #expect(successfulRun.status == .running)
    #expect(successfulRun.worktreePath == secondWorktreeURL.path)
    #expect(try store.runs(taskID: task.id).map(\.status) == [.triggerFailed, .running])
    #expect(try store.runs(taskID: task.id).map(\.worktreePath) == [firstWorktreeURL.path, secondWorktreeURL.path])
    #expect(worktreePreparer.repositories.map(\.id) == [repository.id, repository.id])
}

@Test func codexTriggerBuildsAppServerClientWithConfiguredBinaryPath() async throws {
    let store = try OperatorStore(databaseURL: temporaryDatabaseURL())
    let repository = try store.createRepository(name: "operator", path: "/tmp/operator", defaultBranch: "main")
    let task = try store.createTask(repositoryID: repository.id, title: "Configured", prompt: "Use configured binary")
    let worktreeURL = URL(filePath: "/tmp/operator-worktree-configured")
    let worktreePreparer = FakeCodexWorktreePreparer(preparedWorktrees: [
        PreparedWorktree(worktreeURL: worktreeURL, baseBranch: "main", baseRef: "abc123")
    ])
    let binarySettings = StaticCodexBinarySettingsProvider(
        configuration: CodexBinaryConfiguration(
            detectedBinaryURL: URL(filePath: "/usr/local/bin/codex"),
            overrideBinaryURL: URL(filePath: "/custom/bin/codex")
        )
    )
    let builtClient = FakeCodexAppServerClient(results: [
        .success(startedThread(id: "thread-configured", url: nil))
    ])
    let createdBinaryURLs = CreatedBinaryURLRecorder()
    let factory = ConfiguredCodexAppServerClientFactory(settings: binarySettings) { binaryURL in
        createdBinaryURLs.record(binaryURL)
        return RecordingCodexAppServerClient(binaryURL: binaryURL, client: builtClient)
    }
    let service = CodexTriggerService(
        store: store,
        worktreePreparer: worktreePreparer,
        appServerClientFactory: factory
    )

    let run = try await service.sendTaskToCodex(taskID: task.id)

    #expect(run.status == .running)
    #expect(createdBinaryURLs.urls == [URL(filePath: "/custom/bin/codex")])
    #expect(builtClient.requests.map(\.cwd) == [worktreeURL])
}

@Test func configuredCodexAppServerClientFactoryKeepsCreatedClientAliveForReuse() throws {
    let binarySettings = StaticCodexBinarySettingsProvider(
        configuration: CodexBinaryConfiguration(
            detectedBinaryURL: URL(filePath: "/usr/local/bin/codex"),
            overrideBinaryURL: nil
        )
    )
    let lifetime = ClientLifetimeRecorder()
    let factory = ConfiguredCodexAppServerClientFactory(settings: binarySettings) { _ in
        lifetime.recordCreated()
        return LifetimeRecordingCodexAppServerClient {
            lifetime.recordDeinitialized()
        }
    }

    do {
        _ = try factory.makeAppServerClient()
    }

    #expect(lifetime.createdCount == 1)
    #expect(lifetime.deinitializedCount == 0)

    do {
        _ = try factory.makeAppServerClient()
    }

    #expect(lifetime.createdCount == 1)
    #expect(lifetime.deinitializedCount == 0)
}

@Test func codexTriggerThrowsCodexUnavailableBeforeRecordingRunWhenConfiguredBinaryIsMissing() async throws {
    let store = try OperatorStore(databaseURL: temporaryDatabaseURL())
    let repository = try store.createRepository(name: "operator", path: "/tmp/operator", defaultBranch: "main")
    let task = try store.createTask(repositoryID: repository.id, title: "Missing binary", prompt: "Send")
    let worktreePreparer = FakeCodexWorktreePreparer(preparedWorktrees: [
        PreparedWorktree(
            worktreeURL: URL(filePath: "/tmp/operator-worktree-missing-binary"),
            baseBranch: "main",
            baseRef: "abc123"
        )
    ])
    let factory = ConfiguredCodexAppServerClientFactory(
        settings: StaticCodexBinarySettingsProvider(
            configuration: CodexBinaryConfiguration(detectedBinaryURL: nil, overrideBinaryURL: nil)
        )
    ) { _ in
        FakeCodexAppServerClient(results: [])
    }
    let service = CodexTriggerService(
        store: store,
        worktreePreparer: worktreePreparer,
        appServerClientFactory: factory
    )

    await #expect(throws: CodexBinaryConfigurationError.notFound) {
        try await service.sendTaskToCodex(taskID: task.id)
    }
    #expect(worktreePreparer.repositories.isEmpty)
    #expect(try store.runs(taskID: task.id).isEmpty)
    #expect(try store.task(id: task.id)?.status == .ready)
}

@Test func codexTriggerStripsForbiddenMarkerSubstringsFromFailureErrorMessage() async throws {
    let store = try OperatorStore(databaseURL: temporaryDatabaseURL())
    let repository = try store.createRepository(name: "operator", path: "/tmp/operator", defaultBranch: "main")
    let task = try store.createTask(repositoryID: repository.id, title: "Forbidden markers", prompt: "Send")
    let worktreeURL = URL(filePath: "/tmp/operator-worktree-forbidden-markers")
    let worktreePreparer = FakeCodexWorktreePreparer(preparedWorktrees: [
        PreparedWorktree(worktreeURL: worktreeURL, baseBranch: "main", baseRef: "abc123")
    ])
    let rejectedMessage = "app-server rejected turn rawEvent={\"type\":\"delta\"} transcript=assistant said hi"
    let appServer = FakeCodexAppServerClient(results: [
        .failure(CodexAppServerClientError.serverRejected(message: rejectedMessage))
    ])
    let service = CodexTriggerService(
        store: store,
        worktreePreparer: worktreePreparer,
        appServerClient: appServer
    )

    let run = try await service.sendTaskToCodex(taskID: task.id)

    #expect(run.status == .triggerFailed)
    let storedMessage = try #require(run.errorMessage)
    #expect(storedMessage.contains("rawEvent") == false)
    #expect(storedMessage.contains("transcript") == false)
    #expect(storedMessage.count <= OperatorRuntimeGuardrails.mvp.maximumFailureErrorMessageLength)
}

@Test func codexTriggerRecordsClearFailureWhenCodexAuthenticationIsUnavailable() async throws {
    let store = try OperatorStore(databaseURL: temporaryDatabaseURL())
    let repository = try store.createRepository(name: "operator", path: "/tmp/operator", defaultBranch: "main")
    let task = try store.createTask(repositoryID: repository.id, title: "Auth missing", prompt: "Send")
    let worktreeURL = URL(filePath: "/tmp/operator-worktree-auth-missing")
    let worktreePreparer = FakeCodexWorktreePreparer(preparedWorktrees: [
        PreparedWorktree(worktreeURL: worktreeURL, baseBranch: "main", baseRef: "abc123")
    ])
    let appServer = FakeCodexAppServerClient(results: [
        .failure(CodexAppServerClientError.serverRejected(message: "Codex is not authenticated. Open Codex CLI or App and sign in."))
    ])
    let service = CodexTriggerService(
        store: store,
        worktreePreparer: worktreePreparer,
        appServerClient: appServer
    )

    let run = try await service.sendTaskToCodex(taskID: task.id)

    #expect(run.status == .triggerFailed)
    #expect(run.errorMessage == "Codex is not authenticated. Open Codex CLI or App and sign in.")
    #expect(try store.task(id: task.id)?.status == .ready)
}

@Test func codexTriggerDoesNotPrepareOrSendSuccessfulTaskAgain() async throws {
    let store = try OperatorStore(databaseURL: temporaryDatabaseURL())
    let repository = try store.createRepository(name: "operator", path: "/tmp/operator", defaultBranch: "main")
    let task = try store.createTask(repositoryID: repository.id, title: "Already sent", prompt: "Prompt")
    _ = try store.recordSuccessfulRun(
        taskID: task.id,
        worktreePath: "/tmp/operator-worktree-success",
        baseBranch: "main",
        baseRef: "abc123",
        codexThreadID: "thread-1",
        codexThreadURL: nil
    )
    let worktreePreparer = FakeCodexWorktreePreparer(preparedWorktrees: [])
    let appServer = FakeCodexAppServerClient(results: [])
    let service = CodexTriggerService(
        store: store,
        worktreePreparer: worktreePreparer,
        appServerClient: appServer
    )

    await #expect(throws: TaskLifecycleError.transitionNotAllowed) {
        try await service.sendTaskToCodex(taskID: task.id)
    }
    #expect(worktreePreparer.repositories.isEmpty)
    #expect(appServer.requests.isEmpty)
}

private final class FakeCodexWorktreePreparer: CodexWorktreePreparing, @unchecked Sendable {
    private var preparedWorktrees: [PreparedWorktree]
    private(set) var repositories: [OperatorRepository] = []

    init(preparedWorktrees: [PreparedWorktree]) {
        self.preparedWorktrees = preparedWorktrees
    }

    func prepareWorktree(for repository: OperatorRepository) throws -> PreparedWorktree {
        repositories.append(repository)
        return preparedWorktrees.removeFirst()
    }
}

private final class FakeCodexAppServerClient: CodexAppServerClient, @unchecked Sendable {
    private var results: [Result<CodexStartedThread, Error>]
    private(set) var requests: [CodexThreadStartRequest] = []

    init(results: [Result<CodexStartedThread, Error>]) {
        self.results = results
    }

    func startThreadAndTurn(_ request: CodexThreadStartRequest) async throws -> CodexStartedThread {
        requests.append(request)
        return try results.removeFirst().get()
    }
}

private final class FakeThreadVisibilityController: CodexThreadVisibilityControlling, @unchecked Sendable {
    private let lock = NSLock()
    private var hideCallsValue: [String] = []
    private var revealCallsValue: [String] = []
    private var runStatusAtRevealValue: RunStatus?
    var hideResult = true
    var onReveal: (@Sendable (String) -> Void)?

    var hideCalls: [String] {
        lock.withLock { hideCallsValue }
    }

    var revealCalls: [String] {
        lock.withLock { revealCallsValue }
    }

    var runStatusAtReveal: RunStatus? {
        lock.withLock { runStatusAtRevealValue }
    }

    func recordRunStatusAtReveal(_ status: RunStatus?) {
        lock.withLock {
            runStatusAtRevealValue = status
        }
    }

    func hideThread(id: String) async -> Bool {
        lock.withLock {
            hideCallsValue.append(id)
        }
        return hideResult
    }

    func revealThread(id: String) async -> Bool {
        onReveal?(id)
        lock.withLock {
            revealCallsValue.append(id)
        }
        return true
    }
}

private struct FakeCodexAppServerError: Error, LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}

private final class CreatedBinaryURLRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedURLs: [URL] = []

    var urls: [URL] {
        lock.withLock { recordedURLs }
    }

    func record(_ url: URL) {
        lock.withLock {
            recordedURLs.append(url)
        }
    }
}

private final class StaticCodexBinarySettingsProvider: CodexBinarySettingsProviding, @unchecked Sendable {
    let configurationValue: CodexBinaryConfiguration

    init(configuration: CodexBinaryConfiguration) {
        self.configurationValue = configuration
    }

    func configuration() throws -> CodexBinaryConfiguration {
        configurationValue
    }
}

private final class RecordingCodexAppServerClient: CodexAppServerClient, @unchecked Sendable {
    let binaryURL: URL
    let client: FakeCodexAppServerClient

    init(binaryURL: URL, client: FakeCodexAppServerClient) {
        self.binaryURL = binaryURL
        self.client = client
    }

    func startThreadAndTurn(_ request: CodexThreadStartRequest) async throws -> CodexStartedThread {
        try await client.startThreadAndTurn(request)
    }
}

private final class LifetimeRecordingCodexAppServerClient: CodexAppServerClient, @unchecked Sendable {
    let onDeinit: @Sendable () -> Void

    init(onDeinit: @escaping @Sendable () -> Void) {
        self.onDeinit = onDeinit
    }

    deinit {
        onDeinit()
    }

    func startThreadAndTurn(_ request: CodexThreadStartRequest) async throws -> CodexStartedThread {
        startedThread(id: "thread-lifetime", url: nil)
    }
}

private final class ClientLifetimeRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var createdCountValue = 0
    private var deinitializedCountValue = 0

    var createdCount: Int {
        lock.withLock { createdCountValue }
    }

    var deinitializedCount: Int {
        lock.withLock { deinitializedCountValue }
    }

    func recordCreated() {
        lock.withLock {
            createdCountValue += 1
        }
    }

    func recordDeinitialized() {
        lock.withLock {
            deinitializedCountValue += 1
        }
    }
}

private func startedThread(id: String, url: URL?) -> CodexStartedThread {
    CodexStartedThread(
        reference: CodexThreadReference(id: id, url: url),
        turnCompletion: CodexTurnCompletionSignal()
    )
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

private func temporaryDatabaseURL() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "CodexTriggerServiceTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appending(path: "operator.sqlite")
}
