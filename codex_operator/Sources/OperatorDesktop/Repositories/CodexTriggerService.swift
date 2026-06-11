import Foundation

public struct CodexThreadGitInfo: Equatable, Sendable {
    public let sha: String
    public let branch: String
    public let originURL: String

    public init(sha: String, branch: String, originURL: String) {
        self.sha = sha
        self.branch = branch
        self.originURL = originURL
    }
}

public struct CodexThreadStartRequest: Equatable, Sendable {
    public let cwd: URL
    public let threadCwd: URL
    public let gitInfo: CodexThreadGitInfo?
    public let model: String
    public let reasoningEffort: ReasoningEffort
    public let prompt: String
    public let displayName: String?

    public init(
        cwd: URL,
        threadCwd: URL? = nil,
        gitInfo: CodexThreadGitInfo? = nil,
        model: String,
        reasoningEffort: ReasoningEffort,
        prompt: String,
        displayName: String? = nil
    ) {
        self.cwd = cwd
        self.threadCwd = threadCwd ?? cwd
        self.gitInfo = gitInfo
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.prompt = prompt
        self.displayName = displayName
    }
}

public struct CodexThreadReference: Equatable, Sendable {
    public let id: String
    public let url: URL?

    public init(id: String, url: URL?) {
        self.id = id
        self.url = url
    }

    public static func deepLinkURL(threadID: String) -> URL? {
        URL(string: "codex://threads/\(threadID)")
    }
}

public protocol CodexTurnCompletionWatching: Sendable {
    func waitUntilCompleted() async
}

public actor CodexTurnCompletionSignal: CodexTurnCompletionWatching {
    private var isCompleted: Bool
    private var continuations: [CheckedContinuation<Void, Never>] = []

    public init(isCompleted: Bool = false) {
        self.isCompleted = isCompleted
    }

    public func waitUntilCompleted() async {
        if isCompleted {
            return
        }

        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    public func complete() {
        guard !isCompleted else {
            return
        }
        isCompleted = true
        let continuations = continuations
        self.continuations.removeAll()
        for continuation in continuations {
            continuation.resume()
        }
    }
}

public struct CodexStartedThread: Sendable {
    public let reference: CodexThreadReference
    public let turnCompletion: any CodexTurnCompletionWatching

    public init(reference: CodexThreadReference, turnCompletion: any CodexTurnCompletionWatching) {
        self.reference = reference
        self.turnCompletion = turnCompletion
    }
}

public protocol CodexWorktreePreparing {
    func prepareWorktree(for repository: OperatorRepository) throws -> PreparedWorktree
}

public protocol CodexAppServerClient: Sendable {
    func startThreadAndTurn(_ request: CodexThreadStartRequest) async throws -> CodexStartedThread
}

public protocol CodexAppServerClientFactory: Sendable {
    func makeAppServerClient() throws -> any CodexAppServerClient
}

public protocol CodexTaskSending: Sendable {
    func sendTaskToCodex(taskID: UUID) async throws -> OperatorRun
}

public enum CodexTriggerError: Error, Equatable, LocalizedError, Sendable {
    case repositoryNotFound

    public var errorDescription: String? {
        switch self {
        case .repositoryNotFound:
            "Repository not found."
        }
    }
}

public struct CodexTriggerService: @unchecked Sendable {
    public static let fixedModel = "gpt-5.5"

    private let store: OperatorStore
    private let worktreePreparer: any CodexWorktreePreparing
    private let appServerClientFactory: any CodexAppServerClientFactory
    private let threadVisibility: (any CodexThreadVisibilityControlling)?

    public init(
        store: OperatorStore,
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
        store: OperatorStore,
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
        let task = try store.assertTaskReady(id: taskID)
        guard let repository = try store.repository(id: task.repositoryID) else {
            throw CodexTriggerError.repositoryNotFound
        }

        let preparedWorktree = try worktreePreparer.prepareWorktree(for: repository)
        var hideTask: Task<Bool, Never>?
        var startedThreadID: String?
        do {
            let appServerClient = try appServerClientFactory.makeAppServerClient()
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
                    model: Self.fixedModel,
                    reasoningEffort: task.reasoningEffort,
                    prompt: task.prompt,
                    displayName: task.title
                )
            )
            // Hide the thread from the Codex App sidebar while the turn runs.
            // The rollout file only exists once the turn starts, so this polls
            // concurrently instead of blocking the send flow.
            let threadID = startedThread.reference.id
            startedThreadID = threadID
            if let threadVisibility {
                hideTask = Task {
                    await threadVisibility.hideThread(id: threadID)
                }
            }
            let run = try store.recordStartedRun(
                taskID: task.id,
                worktreePath: preparedWorktree.worktreeURL.path,
                baseBranch: preparedWorktree.baseBranch,
                baseRef: preparedWorktree.baseRef,
                codexThreadID: startedThread.reference.id,
                codexThreadURL: startedThread.reference.url
            )
            let store = store
            let threadVisibility = threadVisibility
            let turnCompletion = startedThread.turnCompletion
            let pendingHideTask = hideTask
            Task {
                await turnCompletion.waitUntilCompleted()
                if let threadVisibility, let pendingHideTask {
                    pendingHideTask.cancel()
                    if await pendingHideTask.value {
                        await threadVisibility.revealThread(id: threadID)
                    }
                }
                _ = try? store.completeStartedRun(id: run.id)
            }
            return run
        } catch {
            if let threadVisibility, let hideTask, let startedThreadID {
                hideTask.cancel()
                Task {
                    if await hideTask.value {
                        await threadVisibility.revealThread(id: startedThreadID)
                    }
                }
            }
            return try store.recordFailedRun(
                taskID: task.id,
                worktreePath: preparedWorktree.worktreeURL.path,
                baseBranch: preparedWorktree.baseBranch,
                baseRef: preparedWorktree.baseRef,
                errorMessage: Self.shortErrorMessage(for: error)
            )
        }
    }

    /// Completes runs that were still marked running when the app last quit.
    /// The spawned app-server dies with the app, so these turns cannot still
    /// be running; reveal their hidden threads and surface the tasks as Done.
    public func recoverInterruptedRuns() async {
        guard let runs = try? store.runningRuns() else {
            return
        }
        for run in runs {
            if let threadVisibility, let threadID = run.codexThreadID {
                await threadVisibility.revealThread(id: threadID)
            }
            _ = try? store.completeStartedRun(id: run.id)
        }
    }

    private static func shortErrorMessage(for error: Error) -> String {
        let message: String
        if let localizedError = error as? LocalizedError, let errorDescription = localizedError.errorDescription {
            message = errorDescription
        } else {
            message = String(describing: error)
        }

        let normalized = message
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ")
        let sanitized = sanitizedFailureErrorMessage(normalized)
        let maximumLength = OperatorRuntimeGuardrails.mvp.maximumFailureErrorMessageLength
        if sanitized.count <= maximumLength {
            return sanitized
        }
        return String(sanitized.prefix(maximumLength - 3)) + "..."
    }

    private static func sanitizedFailureErrorMessage(_ message: String) -> String {
        var sanitized = message
        for forbiddenSubstring in OperatorRuntimeGuardrails.mvp.forbiddenFailureErrorMessageSubstrings {
            sanitized = sanitized.replacingOccurrences(
                of: forbiddenSubstring,
                with: "",
                options: .caseInsensitive
            )
        }
        return sanitized
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension CodexTriggerService: CodexTaskSending {}

private struct FixedCodexAppServerClientFactory: CodexAppServerClientFactory {
    let appServerClient: any CodexAppServerClient

    func makeAppServerClient() throws -> any CodexAppServerClient {
        appServerClient
    }
}

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
