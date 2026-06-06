import Foundation

public struct CodexThreadStartRequest: Equatable, Sendable {
    public let cwd: URL
    public let model: String
    public let reasoningEffort: ReasoningEffort
    public let prompt: String

    public init(cwd: URL, model: String, reasoningEffort: ReasoningEffort, prompt: String) {
        self.cwd = cwd
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.prompt = prompt
    }
}

public struct CodexThreadReference: Equatable, Sendable {
    public let id: String
    public let url: URL?

    public init(id: String, url: URL?) {
        self.id = id
        self.url = url
    }
}

public protocol CodexWorktreePreparing {
    func prepareWorktree(for repository: OperatorRepository) throws -> PreparedWorktree
}

public protocol CodexAppServerClient {
    func startThreadAndTurn(_ request: CodexThreadStartRequest) async throws -> CodexThreadReference
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
    private let appServerClient: any CodexAppServerClient

    public init(
        store: OperatorStore,
        worktreePreparer: any CodexWorktreePreparing,
        appServerClient: any CodexAppServerClient
    ) {
        self.store = store
        self.worktreePreparer = worktreePreparer
        self.appServerClient = appServerClient
    }

    public func sendTaskToCodex(taskID: UUID) async throws -> OperatorRun {
        let task = try store.assertTaskReady(id: taskID)
        guard let repository = try store.repository(id: task.repositoryID) else {
            throw CodexTriggerError.repositoryNotFound
        }

        let preparedWorktree = try worktreePreparer.prepareWorktree(for: repository)
        do {
            let thread = try await appServerClient.startThreadAndTurn(
                CodexThreadStartRequest(
                    cwd: preparedWorktree.worktreeURL,
                    model: Self.fixedModel,
                    reasoningEffort: task.reasoningEffort,
                    prompt: task.prompt
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
        if normalized.count <= 160 {
            return normalized
        }
        return String(normalized.prefix(157)) + "..."
    }
}

extension CodexTriggerService: CodexTaskSending {}
