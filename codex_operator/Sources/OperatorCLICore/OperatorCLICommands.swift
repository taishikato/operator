import Foundation
import OperatorDesktop

// MARK: - Output entities (stable --json schema; see .scratch/operator-skills/PRD.md)

public struct CLIRepository: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let path: String
    public let defaultBranch: String
    public let createdAt: Date
    public let updatedAt: Date

    init(_ repository: OperatorRepository) {
        id = repository.id.uuidString
        name = repository.name
        path = repository.path
        defaultBranch = repository.defaultBranch
        createdAt = repository.createdAt
        updatedAt = repository.updatedAt
    }
}

public struct CLITask: Codable, Equatable, Sendable {
    public let id: String
    public let repositoryID: String
    public let title: String
    public let prompt: String
    public let reasoningEffort: String
    public let status: String
    public let createdAt: Date
    public let updatedAt: Date

    init(_ task: OperatorTask) {
        id = task.id.uuidString
        repositoryID = task.repositoryID.uuidString
        title = task.title
        prompt = task.prompt
        reasoningEffort = task.reasoningEffort.rawValue
        status = task.status.rawValue
        createdAt = task.createdAt
        updatedAt = task.updatedAt
    }
}

public struct CLIRun: Codable, Equatable, Sendable {
    public let id: String
    public let taskID: String
    public let repositoryID: String
    public let status: String
    public let worktreePath: String
    public let baseBranch: String
    public let baseRef: String
    public let codexThreadID: String?
    public let codexThreadURL: String?
    public let errorMessage: String?
    public let createdAt: Date
    public let completedAt: Date?

    init(_ run: OperatorRun) {
        id = run.id.uuidString
        taskID = run.taskID.uuidString
        repositoryID = run.repositoryID.uuidString
        status = run.status.rawValue
        worktreePath = run.worktreePath
        baseBranch = run.baseBranch
        baseRef = run.baseRef
        codexThreadID = run.codexThreadID
        codexThreadURL = run.codexThreadURL?.absoluteString
        errorMessage = run.errorMessage
        createdAt = run.createdAt
        completedAt = run.completedAt
    }

    // Encode nil optionals as explicit JSON null so the key set is stable
    // for agents that validate the schema.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(taskID, forKey: .taskID)
        try container.encode(repositoryID, forKey: .repositoryID)
        try container.encode(status, forKey: .status)
        try container.encode(worktreePath, forKey: .worktreePath)
        try container.encode(baseBranch, forKey: .baseBranch)
        try container.encode(baseRef, forKey: .baseRef)
        try container.encode(codexThreadID, forKey: .codexThreadID)
        try container.encode(codexThreadURL, forKey: .codexThreadURL)
        try container.encode(errorMessage, forKey: .errorMessage)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(completedAt, forKey: .completedAt)
    }
}

// MARK: - Errors

public enum OperatorCLIError: Error, Equatable, Sendable, LocalizedError {
    case repositoryNotFound(String)
    case ambiguousRepositoryName(String)
    case taskNotFound(String)
    case sendFailed(message: String)
    case sendTimedOut(taskID: String)

    public var errorDescription: String? {
        switch self {
        case .repositoryNotFound(let reference):
            "No repository named or identified by '\(reference)'. Run `operator repo list`."
        case .ambiguousRepositoryName(let name):
            "Multiple repositories are named '\(name)'. Use the repository id instead."
        case .taskNotFound(let id):
            "No task with id '\(id)'. Run `operator task list`."
        case .sendFailed(let message):
            "Codex trigger failed: \(message)"
        case .sendTimedOut(let taskID):
            "Timed out waiting for the Codex turn of task '\(taskID)'. Exiting now aborts the turn."
        }
    }
}

// MARK: - Commands

public struct OperatorCLICommands: Sendable {
    private let store: OperatorStore

    public init(store: OperatorStore) {
        self.store = store
    }

    public func listRepositories() throws -> [CLIRepository] {
        try store.repositories().map(CLIRepository.init)
    }

    public func addTask(
        repository: String,
        title: String,
        prompt: String,
        effort: ReasoningEffort
    ) throws -> CLITask {
        let repository = try resolveRepository(repository)
        let task = try store.createTask(
            repositoryID: repository.id,
            title: title,
            prompt: prompt,
            reasoningEffort: effort
        )
        return CLITask(task)
    }

    public func listTasks(repository: String?, status: TaskStatus?) throws -> [CLITask] {
        var tasks = try store.tasks()
        if let repository {
            let repositoryID = try resolveRepository(repository).id
            tasks = tasks.filter { $0.repositoryID == repositoryID }
        }
        if let status {
            tasks = tasks.filter { $0.status == status }
        }
        return tasks.map(CLITask.init)
    }

    public func showTask(id: String) throws -> CLITask {
        CLITask(try resolveTask(id))
    }

    public func archiveTask(id: String) throws -> CLITask {
        let task = try resolveTask(id)
        return CLITask(try store.archiveTask(id: task.id))
    }

    public func listRuns(taskID: String) throws -> [CLIRun] {
        let task = try resolveTask(taskID)
        return try store.runs(taskID: task.id).map(CLIRun.init)
    }

    /// Triggers Codex for a ready task and blocks until the turn completes.
    /// The spawned app-server dies with this process, so returning before
    /// completion would abort the turn — there is deliberately no fire-and-
    /// forget variant (PRD decision 4).
    public func sendTask(
        id: String,
        using trigger: any CodexTaskSending,
        timeout: TimeInterval?,
        pollInterval: TimeInterval = 0.5
    ) async throws -> CLIRun {
        let task = try resolveTask(id)
        let run = try await trigger.sendTaskToCodex(taskID: task.id)

        switch run.status {
        case .triggerFailed:
            throw OperatorCLIError.sendFailed(message: run.errorMessage ?? "trigger failed")
        case .triggered:
            return CLIRun(run)
        case .running:
            return try await waitForCompletion(
                of: run,
                taskID: task.id,
                timeout: timeout,
                pollInterval: pollInterval
            )
        }
    }

    private func waitForCompletion(
        of run: OperatorRun,
        taskID: UUID,
        timeout: TimeInterval?,
        pollInterval: TimeInterval
    ) async throws -> CLIRun {
        let deadline = timeout.map { Date().addingTimeInterval($0) }
        while true {
            let currentRun = try store.runs(taskID: taskID).first { $0.id == run.id } ?? run
            if currentRun.status != .running {
                return CLIRun(currentRun)
            }
            if let deadline, Date() >= deadline {
                throw OperatorCLIError.sendTimedOut(taskID: taskID.uuidString)
            }
            try await Task.sleep(for: .seconds(pollInterval))
        }
    }

    private func resolveRepository(_ reference: String) throws -> OperatorRepository {
        let repositories = try store.repositories()
        if let id = UUID(uuidString: reference),
           let repository = repositories.first(where: { $0.id == id }) {
            return repository
        }
        let named = repositories.filter { $0.name == reference }
        switch named.count {
        case 0:
            throw OperatorCLIError.repositoryNotFound(reference)
        case 1:
            return named[0]
        default:
            throw OperatorCLIError.ambiguousRepositoryName(reference)
        }
    }

    private func resolveTask(_ reference: String) throws -> OperatorTask {
        guard let id = UUID(uuidString: reference), let task = try store.task(id: id) else {
            throw OperatorCLIError.taskNotFound(reference)
        }
        return task
    }
}

// MARK: - Environment

public enum OperatorCLIEnvironment {
    /// Database override for development and testing (`OPERATOR_DB=/path`);
    /// production use relies on the app's default Application Support path so
    /// the CLI and the app always share one board.
    public static func databaseURLOverride(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        environment["OPERATOR_DB"].map { URL(filePath: $0) }
    }
}

// MARK: - JSON output

public enum CLIJSONOutput {
    public static func encode<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    public static func encodeError(_ failure: CLIFailure) throws -> String {
        struct ErrorEnvelope: Encodable {
            struct Payload: Encodable {
                let code: String
                let message: String
            }

            let error: Payload
        }
        return try encode(ErrorEnvelope(error: .init(code: failure.code, message: failure.message)))
    }
}

// MARK: - Error contract

public struct CLIFailure: Equatable, Sendable {
    public let exitCode: Int32
    public let code: String
    public let message: String
}

public func cliFailure(for error: Error) -> CLIFailure {
    let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)

    switch error {
    case OperatorCLIError.repositoryNotFound,
         OperatorCLIError.ambiguousRepositoryName,
         OperatorCLIError.taskNotFound,
         OperatorStoreError.repositoryNotFound,
         OperatorStoreError.taskNotFound,
         CodexTriggerError.repositoryNotFound:
        return CLIFailure(exitCode: 2, code: "notFound", message: message)
    case let lifecycleError as TaskLifecycleError:
        let lifecycleMessage = switch lifecycleError {
        case .transitionNotAllowed:
            "The task lifecycle does not allow this transition."
        case .taskIsImmutable:
            "The task is immutable once sent; only Ready tasks can change."
        case .taskAlreadyHasSuccessfulRun:
            "The task was already sent successfully and cannot be sent again."
        }
        return CLIFailure(exitCode: 3, code: "lifecycleViolation", message: lifecycleMessage)
    case is CodexBinaryConfigurationError:
        return CLIFailure(exitCode: 4, code: "codexUnavailable", message: message)
    case OperatorCLIError.sendFailed,
         is WorktreePreparationError:
        return CLIFailure(exitCode: 5, code: "sendFailed", message: message)
    case OperatorCLIError.sendTimedOut:
        return CLIFailure(exitCode: 6, code: "timeout", message: message)
    default:
        return CLIFailure(exitCode: 70, code: "internal", message: message)
    }
}
