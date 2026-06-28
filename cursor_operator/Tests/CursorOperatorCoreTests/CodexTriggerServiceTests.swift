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
