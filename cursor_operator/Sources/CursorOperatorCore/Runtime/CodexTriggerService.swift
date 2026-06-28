import Foundation

public protocol CodexAppServerClientFactory: Sendable {
    func makeAppServerClient() throws -> any CodexAppServerClient
}

public enum CodexTriggerError: Error, Equatable, LocalizedError, Sendable {
    case repositoryNotFound
    case unsupportedHarness(CursorHarness)

    public var errorDescription: String? {
        switch self {
        case .repositoryNotFound:
            "Repository not found."
        case let .unsupportedHarness(harness):
            "\(harness.displayName) sending is not available yet."
        }
    }
}

public struct CodexTriggerService: @unchecked Sendable {
    private let store: CursorOperatorStore
    private let worktreePreparer: any CodexWorktreePreparing
    private let appServerClientFactory: any CodexAppServerClientFactory

    public init(
        store: CursorOperatorStore,
        worktreePreparer: any CodexWorktreePreparing,
        appServerClient: any CodexAppServerClient
    ) {
        self.init(
            store: store,
            worktreePreparer: worktreePreparer,
            appServerClientFactory: FixedCodexAppServerClientFactory(appServerClient: appServerClient)
        )
    }

    public init(
        store: CursorOperatorStore,
        worktreePreparer: any CodexWorktreePreparing,
        appServerClientFactory: any CodexAppServerClientFactory
    ) {
        self.store = store
        self.worktreePreparer = worktreePreparer
        self.appServerClientFactory = appServerClientFactory
    }

    public func sendTaskToCodex(taskID: UUID) async throws -> OperatorRun {
        guard let task = try store.task(id: taskID) else {
            throw CursorOperatorStoreError.taskNotFound
        }
        guard task.harness == .codex else {
            throw CodexTriggerError.unsupportedHarness(task.harness)
        }
        guard let repository = try store.repository(id: task.repositoryID) else {
            throw CodexTriggerError.repositoryNotFound
        }

        let appServerClient = try appServerClientFactory.makeAppServerClient()
        let preparedWorktree = try worktreePreparer.prepareWorktree(for: repository)
        let startedThread = try await appServerClient.startThreadAndTurn(
            CodexThreadStartRequest(
                cwd: preparedWorktree.worktreeURL,
                gitInfo: preparedWorktree.gitOriginURL.map {
                    CodexThreadGitInfo(
                        sha: preparedWorktree.baseRef,
                        branch: preparedWorktree.baseBranch,
                        originURL: $0
                    )
                },
                model: CodexModel.fixed,
                reasoningEffort: task.reasoningEffort,
                prompt: task.prompt,
                displayName: task.title
            )
        )

        let run = try store.recordStartedCodexRun(
            taskID: task.id,
            worktreeURL: preparedWorktree.worktreeURL,
            baseBranch: preparedWorktree.baseBranch,
            baseRef: preparedWorktree.baseRef,
            codexThreadID: startedThread.reference.id,
            codexThreadURL: startedThread.reference.url
        )
        let store = store
        let turnCompletion = startedThread.turnCompletion
        Task {
            await turnCompletion.waitUntilCompleted()
            _ = try? store.completeStartedCodexRun(id: run.id)
        }
        return run
    }
}

private struct FixedCodexAppServerClientFactory: CodexAppServerClientFactory {
    let appServerClient: any CodexAppServerClient

    func makeAppServerClient() throws -> any CodexAppServerClient {
        appServerClient
    }
}
