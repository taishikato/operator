import Foundation

public struct CodexThreadStartRequest: Equatable, Sendable {
    public let cwd: URL
    public let model: String
    public let reasoningEffort: ReasoningEffort
    public let prompt: String
    public let displayName: String?

    public init(
        cwd: URL,
        model: String,
        reasoningEffort: ReasoningEffort,
        prompt: String,
        displayName: String? = nil
    ) {
        self.cwd = cwd
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

public protocol CodexWorktreePreparing {
    func prepareWorktree(for repository: OperatorRepository) throws -> PreparedWorktree
}

public protocol CodexAppServerClient: Sendable {
    func startThreadAndTurn(_ request: CodexThreadStartRequest) async throws -> CodexThreadReference
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

    public init(
        store: OperatorStore,
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
        store: OperatorStore,
        worktreePreparer: any CodexWorktreePreparing,
        appServerClientFactory: any CodexAppServerClientFactory
    ) {
        self.store = store
        self.worktreePreparer = worktreePreparer
        self.appServerClientFactory = appServerClientFactory
    }

    public func sendTaskToCodex(taskID: UUID) async throws -> OperatorRun {
        let task = try store.assertTaskReady(id: taskID)
        guard let repository = try store.repository(id: task.repositoryID) else {
            throw CodexTriggerError.repositoryNotFound
        }

        let preparedWorktree = try worktreePreparer.prepareWorktree(for: repository)
        do {
            let appServerClient = try appServerClientFactory.makeAppServerClient()
            let thread = try await appServerClient.startThreadAndTurn(
                CodexThreadStartRequest(
                    cwd: preparedWorktree.worktreeURL,
                    model: Self.fixedModel,
                    reasoningEffort: task.reasoningEffort,
                    prompt: task.prompt,
                    displayName: task.title
                )
            )
            return try store.recordSuccessfulRun(
                taskID: task.id,
                worktreePath: preparedWorktree.worktreeURL.path,
                baseBranch: preparedWorktree.baseBranch,
                baseRef: preparedWorktree.baseRef,
                codexThreadID: thread.id,
                codexThreadURL: thread.url
            )
        } catch {
            return try store.recordFailedRun(
                taskID: task.id,
                worktreePath: preparedWorktree.worktreeURL.path,
                baseBranch: preparedWorktree.baseBranch,
                baseRef: preparedWorktree.baseRef,
                errorMessage: Self.shortErrorMessage(for: error)
            )
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
