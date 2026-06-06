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
        PreparedWorktree(worktreeURL: worktreeURL, baseBranch: "main", baseRef: "abc123")
    ])
    let appServer = FakeCodexAppServerClient(results: [
        .success(CodexThreadReference(id: "thread-1", url: URL(string: "codex://thread/thread-1")))
    ])
    let service = CodexTriggerService(
        store: store,
        worktreePreparer: worktreePreparer,
        appServerClient: appServer
    )

    let run = try await service.sendTaskToCodex(taskID: task.id)

    #expect(run.status == .triggered)
    #expect(run.worktreePath == worktreeURL.path)
    #expect(run.baseBranch == "main")
    #expect(run.baseRef == "abc123")
    #expect(run.codexThreadID == "thread-1")
    #expect(run.codexThreadURL == URL(string: "codex://thread/thread-1"))
    #expect(try store.task(id: task.id)?.status == .review)
    #expect(try store.runs(taskID: task.id).map(\.id) == [run.id])
    #expect(worktreePreparer.repositories.map(\.id) == [repository.id])
    #expect(appServer.requests == [
        CodexThreadStartRequest(
            cwd: worktreeURL,
            model: "gpt-5.5",
            reasoningEffort: .high,
            prompt: "Implement this exactly.\nDo not add metadata."
        )
    ])
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
        .success(CodexThreadReference(id: "thread-retry", url: nil))
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

    #expect(successfulRun.status == .triggered)
    #expect(successfulRun.worktreePath == secondWorktreeURL.path)
    #expect(try store.runs(taskID: task.id).map(\.status) == [.triggerFailed, .triggered])
    #expect(try store.runs(taskID: task.id).map(\.worktreePath) == [firstWorktreeURL.path, secondWorktreeURL.path])
    #expect(worktreePreparer.repositories.map(\.id) == [repository.id, repository.id])
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
    private var results: [Result<CodexThreadReference, Error>]
    private(set) var requests: [CodexThreadStartRequest] = []

    init(results: [Result<CodexThreadReference, Error>]) {
        self.results = results
    }

    func startThreadAndTurn(_ request: CodexThreadStartRequest) async throws -> CodexThreadReference {
        requests.append(request)
        return try results.removeFirst().get()
    }
}

private struct FakeCodexAppServerError: Error, LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}

private func temporaryDatabaseURL() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "CodexTriggerServiceTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appending(path: "operator.sqlite")
}
