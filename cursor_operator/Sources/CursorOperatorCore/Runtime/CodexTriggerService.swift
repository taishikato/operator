import Foundation

public protocol CodexAppServerClientFactory: Sendable {
    func makeAppServerClient() throws -> any CodexAppServerClient
}

public protocol CodexTaskSending: Sendable {
    func sendTaskToCodex(taskID: UUID) async throws -> OperatorRun
}

public protocol CodexRunRecovering: Sendable {
    func recoverInterruptedRuns() async
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
    private let threadVisibility: (any CodexThreadVisibilityControlling)?

    public init(
        store: CursorOperatorStore,
        worktreePreparer: any CodexWorktreePreparing,
        appServerClient: any CodexAppServerClient,
        threadVisibility: (any CodexThreadVisibilityControlling)? = nil
    ) {
        self.init(
            store: store,
            worktreePreparer: worktreePreparer,
            appServerClientFactory: FixedCodexAppServerClientFactory(appServerClient: appServerClient),
            threadVisibility: threadVisibility
        )
    }

    public init(
        store: CursorOperatorStore,
        worktreePreparer: any CodexWorktreePreparing,
        appServerClientFactory: any CodexAppServerClientFactory,
        threadVisibility: (any CodexThreadVisibilityControlling)? = nil
    ) {
        self.store = store
        self.worktreePreparer = worktreePreparer
        self.appServerClientFactory = appServerClientFactory
        self.threadVisibility = threadVisibility
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
        let startedThread: CodexStartedThread
        do {
            startedThread = try await appServerClient.startThreadAndTurn(
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
        } catch {
            return try store.recordFailedCodexRun(
                taskID: task.id,
                worktreeURL: preparedWorktree.worktreeURL,
                baseBranch: preparedWorktree.baseBranch,
                baseRef: preparedWorktree.baseRef,
                errorMessage: Self.shortErrorMessage(for: error)
            )
        }

        let threadID = startedThread.reference.id
        let hideTask: Task<Bool, Never>? = threadVisibility.map { threadVisibility in
            Task {
                await threadVisibility.hideThread(id: threadID)
            }
        }
        let run = try store.recordStartedCodexRun(
            taskID: task.id,
            worktreeURL: preparedWorktree.worktreeURL,
            baseBranch: preparedWorktree.baseBranch,
            baseRef: preparedWorktree.baseRef,
            codexThreadID: threadID,
            codexThreadURL: startedThread.reference.url
        )
        let store = store
        let threadVisibility = threadVisibility
        let turnCompletion = startedThread.turnCompletion
        let retainedAppServerClient = appServerClient
        Task {
            let outcome = await turnCompletion.waitUntilCompleted()
            if let threadVisibility, let hideTask {
                hideTask.cancel()
                if await hideTask.value {
                    await threadVisibility.revealThread(id: threadID)
                }
            }
            switch outcome {
            case .succeeded:
                _ = try? store.completeStartedCodexRun(id: run.id)
            case let .failed(message):
                _ = try? store.failStartedCodexRun(
                    id: run.id,
                    errorMessage: Self.shortErrorMessage(forMessage: message)
                )
            }
            _ = retainedAppServerClient
        }
        return run
    }

    public func recoverInterruptedRuns() async {
        guard let runs = try? store.runningCodexRuns() else {
            return
        }
        for run in runs {
            if let threadVisibility, let threadID = run.codexThreadID {
                _ = await threadVisibility.revealThread(id: threadID)
            }
            _ = try? store.failStartedCodexRun(
                id: run.id,
                errorMessage: "Codex run was interrupted before the initial turn completed."
            )
        }
    }

    private static func shortErrorMessage(for error: Error) -> String {
        let rawMessage: String
        if let localizedError = error as? LocalizedError, let errorDescription = localizedError.errorDescription {
            rawMessage = errorDescription
        } else {
            rawMessage = String(describing: error)
        }

        return shortErrorMessage(forMessage: rawMessage)
    }

    private static func shortErrorMessage(forMessage rawMessage: String) -> String {
        let collapsed = rawMessage
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsed.isEmpty else {
            return "Codex run failed."
        }

        let sensitiveMarkers = ["{", "body", "authorization", "bearer", "cookie", "token", "secret", "password", "api_key", "apikey"]
        if sensitiveMarkers.contains(where: { collapsed.range(of: $0, options: .caseInsensitive) != nil }) {
            return "Codex run failed. See Codex for details."
        }
        if collapsed.count > 160 {
            return "\(collapsed.prefix(157))..."
        }
        return collapsed
    }
}

private struct FixedCodexAppServerClientFactory: CodexAppServerClientFactory {
    let appServerClient: any CodexAppServerClient

    func makeAppServerClient() throws -> any CodexAppServerClient {
        appServerClient
    }
}

extension CodexTriggerService: CodexTaskSending {}

extension CodexTriggerService: CodexRunRecovering {}

public final class ConfiguredCodexAppServerClientFactory: CodexAppServerClientFactory, @unchecked Sendable {
    private let settings: any CodexBinarySettingsProviding
    private let makeClient: @Sendable (URL) -> any CodexAppServerClient
    private let lock = NSLock()
    private var cachedBinaryURL: URL?
    private var cachedAppServerClient: (any CodexAppServerClient)?

    public init(
        settings: any CodexBinarySettingsProviding = CodexBinarySettings(),
        makeClient: @escaping @Sendable (URL) -> any CodexAppServerClient = { binaryURL in
            CodexAppServerStdioClient(codexBinaryURL: binaryURL)
        }
    ) {
        self.settings = settings
        self.makeClient = makeClient
    }

    public func makeAppServerClient() throws -> any CodexAppServerClient {
        lock.lock()
        defer {
            lock.unlock()
        }

        guard let binaryURL = try settings.configuration().effectiveBinaryURL else {
            throw CodexBinaryConfigurationError.notFound
        }
        if let cachedAppServerClient, cachedBinaryURL == binaryURL {
            return cachedAppServerClient
        }

        let appServerClient = makeClient(binaryURL)
        cachedBinaryURL = binaryURL
        cachedAppServerClient = appServerClient
        return appServerClient
    }
}
