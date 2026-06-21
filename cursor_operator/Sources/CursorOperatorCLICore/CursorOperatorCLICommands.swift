import Foundation
import CursorOperatorCore

// MARK: - Output entities

public struct CursorCLIRepository: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let localPath: String
    public let githubURL: String
    public let defaultBranch: String
    public let createdAt: Date
    public let updatedAt: Date

    init(_ repository: CursorRepository) {
        id = repository.id.uuidString
        name = repository.name
        localPath = repository.localPath
        githubURL = repository.githubURL.absoluteString
        defaultBranch = repository.defaultBranch
        createdAt = repository.createdAt
        updatedAt = repository.updatedAt
    }
}

public struct CursorCLITask: Codable, Equatable, Sendable {
    public let id: String
    public let repositoryID: String
    public let title: String
    public let prompt: String
    public let autoCreatePR: Bool
    public let status: String
    public let createdAt: Date
    public let updatedAt: Date

    init(_ task: CursorTask) {
        id = task.id.uuidString
        repositoryID = task.repositoryID.uuidString
        title = task.title
        prompt = task.prompt
        autoCreatePR = task.autoCreatePR
        status = task.status.rawValue
        createdAt = task.createdAt
        updatedAt = task.updatedAt
    }
}

public struct CursorCLIRunAttempt: Codable, Equatable, Sendable {
    public let id: String
    public let taskID: String
    public let repositoryID: String
    public let status: String
    public let repositoryURL: String
    public let startingRef: String
    public let model: String
    public let autoCreatePR: Bool
    public let prompt: String
    public let cursorAgentID: String?
    public let cursorRunID: String?
    public let cursorURL: String?
    public let errorMessage: String?
    public let createdAt: Date
    public let completedAt: Date

    init(_ attempt: CursorRunAttempt) {
        id = attempt.id.uuidString
        taskID = attempt.taskID.uuidString
        repositoryID = attempt.repositoryID.uuidString
        status = attempt.status.rawValue
        repositoryURL = attempt.repositoryURL.absoluteString
        startingRef = attempt.startingRef
        model = attempt.model
        autoCreatePR = attempt.autoCreatePR
        prompt = attempt.prompt
        cursorAgentID = attempt.cursorAgentID
        cursorRunID = attempt.cursorRunID
        cursorURL = attempt.cursorURL?.absoluteString
        errorMessage = attempt.errorMessage
        createdAt = attempt.createdAt
        completedAt = attempt.completedAt
    }

    // Encode nil optionals as JSON null so agents can rely on a stable key set.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(taskID, forKey: .taskID)
        try container.encode(repositoryID, forKey: .repositoryID)
        try container.encode(status, forKey: .status)
        try container.encode(repositoryURL, forKey: .repositoryURL)
        try container.encode(startingRef, forKey: .startingRef)
        try container.encode(model, forKey: .model)
        try container.encode(autoCreatePR, forKey: .autoCreatePR)
        try container.encode(prompt, forKey: .prompt)
        try container.encode(cursorAgentID, forKey: .cursorAgentID)
        try container.encode(cursorRunID, forKey: .cursorRunID)
        try container.encode(cursorURL, forKey: .cursorURL)
        try container.encode(errorMessage, forKey: .errorMessage)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(completedAt, forKey: .completedAt)
    }
}

// MARK: - Errors

public enum CursorOperatorCLIError: Error, Equatable, Sendable, LocalizedError {
    case repositoryNotFound(String)
    case ambiguousRepositoryName(String)
    case taskNotFound(String)
    case sendFailed(message: String)

    public var errorDescription: String? {
        switch self {
        case .repositoryNotFound(let reference):
            "No Cursor repository named or identified by '\(reference)'. Run `cursor-operator repo list`."
        case .ambiguousRepositoryName(let name):
            "Multiple Cursor repositories are named '\(name)'. Use the repository id instead."
        case .taskNotFound(let id):
            "No Cursor task with id '\(id)'. Run `cursor-operator task list`."
        case .sendFailed(let message):
            "Cursor send failed: \(message)"
        }
    }
}

// MARK: - Commands

public struct CursorOperatorCLICommands: Sendable {
    private let store: CursorOperatorStore
    private let repositoryInspector: any CursorRepositoryInspecting
    private let credentialProvider: CursorCredentialProvider
    private let runtime: any CursorCloudAgentRuntime

    public init(
        store: CursorOperatorStore,
        repositoryInspector: any CursorRepositoryInspecting = CursorGitRepositoryInspector(),
        credentialProvider: CursorCredentialProvider = CursorCredentialProvider(store: KeychainCursorCredentialStore()),
        runtime: any CursorCloudAgentRuntime = CursorCloudAgentSDKRuntime()
    ) {
        self.store = store
        self.repositoryInspector = repositoryInspector
        self.credentialProvider = credentialProvider
        self.runtime = runtime
    }

    public func listRepositories() throws -> [CursorCLIRepository] {
        try store.repositories().map(CursorCLIRepository.init)
    }

    public func addRepository(path: String) throws -> CursorCLIRepository {
        let service = CursorRepositoryRegistrationService(store: store, inspector: repositoryInspector)
        let draft = try service.prepareRepository(at: URL(filePath: path).standardizedFileURL)
        return CursorCLIRepository(try service.saveRepository(draft))
    }

    public func addTask(
        repository: String,
        title: String,
        prompt: String,
        autoCreatePR: Bool
    ) throws -> CursorCLITask {
        let repository = try resolveRepository(repository)
        let task = try CursorTaskCreationDraft(
            repositoryID: repository.id,
            title: title,
            prompt: prompt,
            autoCreatePR: autoCreatePR
        ).createTask(in: store)
        return CursorCLITask(task)
    }

    public func listTasks(repository: String?, status: CursorTaskStatus?) throws -> [CursorCLITask] {
        var tasks = try store.tasks()
        if let repository {
            let repositoryID = try resolveRepository(repository).id
            tasks = tasks.filter { $0.repositoryID == repositoryID }
        }
        if let status {
            tasks = tasks.filter { $0.status == status }
        }
        return tasks.map(CursorCLITask.init)
    }

    public func showTask(id: String) throws -> CursorCLITask {
        CursorCLITask(try resolveTask(id))
    }

    public func archiveTask(id: String) throws -> CursorCLITask {
        let task = try resolveTask(id)
        return CursorCLITask(try store.archiveTask(id: task.id))
    }

    public func listRuns(taskID: String) throws -> [CursorCLIRunAttempt] {
        let task = try resolveTask(taskID)
        return try store.runAttempts(taskID: task.id).map(CursorCLIRunAttempt.init)
    }

    public func sendTask(id: String, wait: Bool) async throws -> CursorCLIRunAttempt {
        let task = try resolveTask(id)
        let service = CursorTaskSendService(
            store: store,
            credentialReadiness: CursorSendReadiness(provider: credentialProvider),
            runtime: runtime
        )
        let attempt = try await service.send(taskID: task.id)
        guard attempt.status == .succeeded else {
            throw CursorOperatorCLIError.sendFailed(message: attempt.errorMessage ?? "Cursor did not start the run.")
        }

        if wait {
            try await waitForRun(taskID: task.id, runID: attempt.cursorRunID)
        }
        return CursorCLIRunAttempt(attempt)
    }

    private func waitForRun(taskID: UUID, runID: String?) async throws {
        let monitor = CursorRunMonitorService(
            store: store,
            credentialReadiness: CursorSendReadiness(provider: credentialProvider),
            runtime: runtime
        )
        let outcomes = try await monitor.resumeRunningTasks()
        guard let runID,
              let outcome = outcomes.first(where: { $0.runID == runID }) else {
            return
        }
        switch outcome {
        case .completed:
            return
        case .failed(_, _, let message),
             .monitoringFailed(_, _, let message):
            throw CursorOperatorCLIError.sendFailed(message: message)
        case .stillRunning:
            if try store.task(id: taskID)?.status == .failed {
                throw CursorOperatorCLIError.sendFailed(message: "Cursor run failed.")
            }
        }
    }

    private func resolveRepository(_ reference: String) throws -> CursorRepository {
        let repositories = try store.repositories()
        if let id = UUID(uuidString: reference),
           let repository = repositories.first(where: { $0.id == id }) {
            return repository
        }
        let named = repositories.filter { $0.name == reference }
        switch named.count {
        case 0:
            throw CursorOperatorCLIError.repositoryNotFound(reference)
        case 1:
            return named[0]
        default:
            throw CursorOperatorCLIError.ambiguousRepositoryName(reference)
        }
    }

    private func resolveTask(_ reference: String) throws -> CursorTask {
        guard let id = UUID(uuidString: reference), let task = try store.task(id: id) else {
            throw CursorOperatorCLIError.taskNotFound(reference)
        }
        return task
    }
}

private extension CursorRunMonitorOutcome {
    var runID: String {
        switch self {
        case .completed(_, let runID),
             .failed(_, let runID, _),
             .monitoringFailed(_, let runID, _),
             .stillRunning(_, let runID):
            runID
        }
    }
}

// MARK: - Environment

public enum CursorOperatorCLIEnvironment {
    public static func databaseURLOverride(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        environment["CURSOR_OPERATOR_DB"].map { URL(filePath: $0) }
    }
}

// MARK: - JSON output

public enum CursorCLIJSONOutput {
    public static func encode<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    public static func encodeError(_ failure: CursorCLIFailure) throws -> String {
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

public struct CursorCLIFailure: Equatable, Sendable {
    public let exitCode: Int32
    public let code: String
    public let message: String

    public init(exitCode: Int32, code: String, message: String) {
        self.exitCode = exitCode
        self.code = code
        self.message = message
    }
}

public func cursorCLIFailure(for error: Error) -> CursorCLIFailure {
    let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)

    switch error {
    case CursorOperatorCLIError.repositoryNotFound,
         CursorOperatorCLIError.ambiguousRepositoryName,
         CursorOperatorCLIError.taskNotFound,
         CursorOperatorStoreError.repositoryNotFound,
         CursorOperatorStoreError.taskNotFound:
        return CursorCLIFailure(exitCode: 2, code: "notFound", message: message)
    case let lifecycleError as CursorTaskLifecycleError:
        let lifecycleMessage = switch lifecycleError {
        case .transitionNotAllowed:
            "The Cursor task lifecycle does not allow this transition."
        case .taskIsImmutable:
            "The Cursor task is immutable once sent; only Ready tasks can change."
        case .taskAlreadyHasSuccessfulRun:
            "The Cursor task is already being sent or already has a Cursor run."
        case .hardDeleteNotAllowed:
            "Cursor tasks can be archived, but not permanently deleted."
        }
        return CursorCLIFailure(exitCode: 3, code: "lifecycleViolation", message: lifecycleMessage)
    case CursorTaskSendError.missingCredentials:
        return CursorCLIFailure(exitCode: 4, code: "cursorUnavailable", message: message)
    case CursorOperatorCLIError.sendFailed,
         CursorTaskSendError.startedRunCouldNotBeRecorded,
         is CursorRuntimeFailure,
         is CursorNodeResolutionError:
        return CursorCLIFailure(exitCode: 5, code: "sendFailed", message: message)
    case is CursorRepositoryRegistrationError:
        return CursorCLIFailure(exitCode: 7, code: "invalidRepository", message: message)
    case CursorOperatorStoreError.repositoryPathAlreadyRegistered(let existingID):
        return CursorCLIFailure(
            exitCode: 8,
            code: "alreadyRegistered",
            message: "This Cursor repository is already registered (id: \(existingID.uuidString)). Use it directly."
        )
    default:
        return CursorCLIFailure(exitCode: 70, code: "internal", message: message)
    }
}
