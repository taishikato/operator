import Foundation
import Testing
@testable import CursorOperatorCore

@Test func codexTriggerStartsThreadFromPreparedWorktreeAndRecordsRunningRun() async throws {
    let store = try CursorOperatorStore(databaseURL: temporaryDatabaseURL())
    let repository = try store.createRepository(
        name: "operator",
        localPath: "/tmp/operator",
        githubURL: URL(string: "https://github.com/taishikato/operator")!,
        defaultBranch: "main"
    )
    let task = try store.createTask(
        repositoryID: repository.id,
        title: "Exact prompt",
        prompt: "Implement this exactly.\nDo not add metadata.",
        reasoningEffort: .high,
        harness: .codex
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
    #expect(run.harness == .codex)
    #expect(run.repositoryURL == worktreeURL)
    #expect(run.startingRef == "abc123")
    #expect(run.baseBranch == "main")
    #expect(run.baseRef == "abc123")
    #expect(run.codexThreadID == "thread-1")
    #expect(run.codexThreadURL == URL(string: "codex://threads/thread-1"))
    #expect(try store.task(id: task.id)?.status == .running)
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
            model: CodexModel.fixed,
            reasoningEffort: .high,
            prompt: "Implement this exactly.\nDo not add metadata.",
            displayName: "Exact prompt"
        )
    ])
}

@Test func codexTriggerCompletesRunAndTaskAfterInitialTurnCompletion() async throws {
    let store = try CursorOperatorStore(databaseURL: temporaryDatabaseURL())
    let repository = try store.createRepository(
        name: "operator",
        localPath: "/tmp/operator",
        githubURL: URL(string: "https://github.com/taishikato/operator")!,
        defaultBranch: "main"
    )
    let task = try store.createTask(
        repositoryID: repository.id,
        title: "Wait for turn",
        prompt: "Prompt",
        harness: .codex
    )
    let worktreePreparer = FakeCodexWorktreePreparer(preparedWorktrees: [
        PreparedWorktree(worktreeURL: URL(filePath: "/tmp/operator-worktree-running"), baseBranch: "main", baseRef: "abc123")
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
    #expect(try store.task(id: task.id)?.status == .running)

    await turnCompletion.complete()
    await waitUntil {
        ((try? store.task(id: task.id)?.status) ?? nil) == .done
    }

    #expect(try store.runs(taskID: task.id).first?.id == run.id)
    #expect(try store.runs(taskID: task.id).first?.status == .succeeded)
    #expect(try store.task(id: task.id)?.status == .done)
}

@Test func codexTriggerKeepsAppServerClientAliveUntilInitialTurnCompletion() async throws {
    let store = try CursorOperatorStore(databaseURL: temporaryDatabaseURL())
    let repository = try store.createRepository(
        name: "operator",
        localPath: "/tmp/operator",
        githubURL: URL(string: "https://github.com/taishikato/operator")!,
        defaultBranch: "main"
    )
    let task = try store.createTask(repositoryID: repository.id, title: "Keep alive", prompt: "Prompt", harness: .codex)
    let worktreePreparer = FakeCodexWorktreePreparer(preparedWorktrees: [
        PreparedWorktree(worktreeURL: URL(filePath: "/tmp/operator-worktree-keepalive"), baseBranch: "main", baseRef: "abc123")
    ])
    let turnCompletion = CodexTurnCompletionSignal()
    let deallocationRecorder = DeallocationRecorder()
    let appServerFactory = DeinitTrackingCodexAppServerClientFactory(
        startedThread: CodexStartedThread(
            reference: CodexThreadReference(id: "thread-keepalive", url: nil),
            turnCompletion: turnCompletion
        ),
        deallocationRecorder: deallocationRecorder
    )
    let service = CodexTriggerService(
        store: store,
        worktreePreparer: worktreePreparer,
        appServerClientFactory: appServerFactory
    )

    _ = try await service.sendTaskToCodex(taskID: task.id)
    await Task.yield()

    #expect(deallocationRecorder.isDeallocated == false)

    await turnCompletion.complete()
    await waitUntil {
        ((try? store.task(id: task.id)?.status) ?? nil) == .done
    }
    await waitUntil {
        deallocationRecorder.isDeallocated
    }

    #expect(deallocationRecorder.isDeallocated)
}

@Test func codexTriggerMarksRunFailedWhenInitialTurnAborts() async throws {
    let store = try CursorOperatorStore(databaseURL: temporaryDatabaseURL())
    let repository = try store.createRepository(
        name: "operator",
        localPath: "/tmp/operator",
        githubURL: URL(string: "https://github.com/taishikato/operator")!,
        defaultBranch: "main"
    )
    let task = try store.createTask(repositoryID: repository.id, title: "Abort", prompt: "Prompt", harness: .codex)
    let worktreePreparer = FakeCodexWorktreePreparer(preparedWorktrees: [
        PreparedWorktree(worktreeURL: URL(filePath: "/tmp/operator-worktree-aborted"), baseBranch: "main", baseRef: "abc123")
    ])
    let turnCompletion = CodexTurnCompletionSignal()
    let appServer = FakeCodexAppServerClient(results: [
        .success(CodexStartedThread(
            reference: CodexThreadReference(id: "thread-aborted", url: URL(string: "codex://threads/thread-aborted")),
            turnCompletion: turnCompletion
        ))
    ])
    let service = CodexTriggerService(
        store: store,
        worktreePreparer: worktreePreparer,
        appServerClient: appServer
    )

    let run = try await service.sendTaskToCodex(taskID: task.id)
    await turnCompletion.complete(.failed(message: "Codex turn was aborted."))
    await waitUntil {
        ((try? store.task(id: task.id)?.status) ?? nil) == .failed
    }

    #expect(try store.runs(taskID: task.id).first?.id == run.id)
    #expect(try store.runs(taskID: task.id).first?.status == .failed)
    #expect(try store.runs(taskID: task.id).first?.errorMessage == "Codex turn was aborted.")
    #expect(try store.task(id: task.id)?.status == .failed)
}

@Test func codexTriggerRecordsProviderFailureAndMarksTaskFailed() async throws {
    let store = try CursorOperatorStore(databaseURL: temporaryDatabaseURL())
    let repository = try store.createRepository(
        name: "operator",
        localPath: "/tmp/operator",
        githubURL: URL(string: "https://github.com/taishikato/operator")!,
        defaultBranch: "main"
    )
    let task = try store.createTask(
        repositoryID: repository.id,
        title: "Failure",
        prompt: "Prompt",
        harness: .codex
    )
    let worktreeURL = URL(filePath: "/tmp/operator-worktree-failed")
    let worktreePreparer = FakeCodexWorktreePreparer(preparedWorktrees: [
        PreparedWorktree(worktreeURL: worktreeURL, baseBranch: "main", baseRef: "abc123")
    ])
    let appServer = FakeCodexAppServerClient(results: [
        .failure(CodexAppServerClientError.serverRejected(message: "body { token: secret }"))
    ])
    let service = CodexTriggerService(
        store: store,
        worktreePreparer: worktreePreparer,
        appServerClient: appServer
    )

    let run = try await service.sendTaskToCodex(taskID: task.id)

    #expect(run.status == .failed)
    #expect(run.harness == .codex)
    #expect(run.worktreePath == worktreeURL.path)
    #expect(run.errorMessage == "Codex run failed. See Codex for details.")
    #expect(try store.task(id: task.id)?.status == .failed)
}

@Test func codexTriggerRevealsHiddenThreadBeforeCompletingRun() async throws {
    let store = try CursorOperatorStore(databaseURL: temporaryDatabaseURL())
    let repository = try store.createRepository(
        name: "operator",
        localPath: "/tmp/operator",
        githubURL: URL(string: "https://github.com/taishikato/operator")!,
        defaultBranch: "main"
    )
    let task = try store.createTask(repositoryID: repository.id, title: "Hidden", prompt: "Prompt", harness: .codex)
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
    visibility.onReveal = { [store] _ in
        visibility.recordTaskStatusAtReveal((try? store.task(id: task.id)?.status) ?? nil)
    }
    let service = CodexTriggerService(
        store: store,
        worktreePreparer: worktreePreparer,
        appServerClient: appServer,
        threadVisibility: visibility
    )

    _ = try await service.sendTaskToCodex(taskID: task.id)
    await waitUntil { visibility.hideCalls == ["thread-hidden"] }
    await turnCompletion.complete()
    await waitUntil {
        ((try? store.task(id: task.id)?.status) ?? nil) == .done
    }

    #expect(visibility.hideCalls == ["thread-hidden"])
    #expect(visibility.revealCalls == ["thread-hidden"])
    #expect(visibility.taskStatusAtReveal == .running)
    #expect(try store.task(id: task.id)?.status == .done)
}

private final class FakeCodexWorktreePreparer: CodexWorktreePreparing, @unchecked Sendable {
    private var preparedWorktrees: [PreparedWorktree]
    private(set) var repositories: [CursorRepository] = []

    init(preparedWorktrees: [PreparedWorktree]) {
        self.preparedWorktrees = preparedWorktrees
    }

    func prepareWorktree(for repository: CursorRepository) throws -> PreparedWorktree {
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

private final class DeinitTrackingCodexAppServerClientFactory: CodexAppServerClientFactory, @unchecked Sendable {
    private let startedThread: CodexStartedThread
    private let deallocationRecorder: DeallocationRecorder

    init(startedThread: CodexStartedThread, deallocationRecorder: DeallocationRecorder) {
        self.startedThread = startedThread
        self.deallocationRecorder = deallocationRecorder
    }

    func makeAppServerClient() throws -> any CodexAppServerClient {
        DeinitTrackingCodexAppServerClient(
            startedThread: startedThread,
            deallocationRecorder: deallocationRecorder
        )
    }
}

private final class DeinitTrackingCodexAppServerClient: CodexAppServerClient, @unchecked Sendable {
    private let startedThread: CodexStartedThread
    private let deallocationRecorder: DeallocationRecorder

    init(startedThread: CodexStartedThread, deallocationRecorder: DeallocationRecorder) {
        self.startedThread = startedThread
        self.deallocationRecorder = deallocationRecorder
    }

    deinit {
        deallocationRecorder.recordDeallocation()
    }

    func startThreadAndTurn(_ request: CodexThreadStartRequest) async throws -> CodexStartedThread {
        startedThread
    }
}

private final class DeallocationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var isDeallocatedValue = false

    var isDeallocated: Bool {
        lock.withLock { isDeallocatedValue }
    }

    func recordDeallocation() {
        lock.withLock {
            isDeallocatedValue = true
        }
    }
}

private final class FakeThreadVisibilityController: CodexThreadVisibilityControlling, @unchecked Sendable {
    private let lock = NSLock()
    private var hideCallsValue: [String] = []
    private var revealCallsValue: [String] = []
    private var taskStatusAtRevealValue: CursorTaskStatus?
    var hideResult = true
    var onReveal: (@Sendable (String) -> Void)?

    var hideCalls: [String] {
        lock.withLock { hideCallsValue }
    }

    var revealCalls: [String] {
        lock.withLock { revealCallsValue }
    }

    var taskStatusAtReveal: CursorTaskStatus? {
        lock.withLock { taskStatusAtRevealValue }
    }

    func recordTaskStatusAtReveal(_ status: CursorTaskStatus?) {
        lock.withLock {
            taskStatusAtRevealValue = status
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

private func startedThread(id: String, url: URL?) -> CodexStartedThread {
    CodexStartedThread(
        reference: CodexThreadReference(id: id, url: url),
        turnCompletion: CodexTurnCompletionSignal()
    )
}

private func temporaryDatabaseURL() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "CodexTriggerServiceTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appending(path: "operator.sqlite")
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
