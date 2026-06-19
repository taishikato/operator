import Combine
import Foundation

@MainActor
public final class CursorBoardModel: ObservableObject {
    @Published public private(set) var projection: CursorBoardProjection
    @Published public private(set) var repositories: [CursorRepository]
    @Published public private(set) var setupStatus: CursorSetupStatusProjection
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var pendingRepositoryDraft: CursorRepositoryRegistrationDraft?
    @Published public var creationDraft: CursorTaskCreationDraft

    private let store: CursorOperatorStore
    private let repositoryRegistrationService: CursorRepositoryRegistrationService
    private let credentialProvider: CursorCredentialProvider
    private let runtime: any CursorCloudAgentRuntime
    private let externalOpener: any CursorExternalOpening

    public init(
        store: CursorOperatorStore,
        repositoryInspector: any CursorRepositoryInspecting = CursorGitRepositoryInspector(),
        credentialProvider: CursorCredentialProvider = CursorCredentialProvider(store: KeychainCursorCredentialStore()),
        runtime: any CursorCloudAgentRuntime = CursorCloudAgentSDKRuntime(),
        externalOpener: any CursorExternalOpening = SystemCursorExternalOpener()
    ) {
        self.store = store
        self.credentialProvider = credentialProvider
        self.runtime = runtime
        self.externalOpener = externalOpener
        repositoryRegistrationService = CursorRepositoryRegistrationService(
            store: store,
            inspector: repositoryInspector
        )
        projection = CursorBoardProjection(tasks: [])
        repositories = []
        setupStatus = .empty
        creationDraft = CursorTaskCreationDraft()
    }

    public func load() throws {
        repositories = try store.repositories()
        setupStatus = try CursorSetupStatusProjection(
            repositoryState: repositories.isEmpty ? .missing : .registered(count: repositories.count),
            credentialState: CursorSendReadiness(provider: credentialProvider).credentialState()
        )
        projection = try CursorBoardProjection.load(from: store)
        errorMessage = nil
    }

    public func createLocalTask(title: String, prompt: String) throws {
        let repository = try firstRepositoryOrCreatePlaceholder()
        _ = try store.createTask(
            repositoryID: repository.id,
            title: title,
            prompt: prompt
        )
        try load()
    }

    public func createTaskFromDraft() throws -> CursorTask {
        let task = try creationDraft.createTask(in: store)
        creationDraft = CursorTaskCreationDraft(repositoryID: creationDraft.repositoryID)
        try load()
        return task
    }

    public func prepareCreateTaskDraftForPresentation() -> Bool {
        if creationDraft.repositoryID == nil {
            creationDraft.repositoryID = repositories.first?.id
        }
        guard creationDraft.repositoryID != nil else {
            errorMessage = "Register a repository before creating a task."
            return false
        }
        return true
    }

    public func updateTaskFromDraft(taskID: UUID) throws -> CursorTask {
        guard !creationDraft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CursorTaskCreationError.titleRequired
        }
        guard !creationDraft.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CursorTaskCreationError.promptRequired
        }

        let task = try store.updateTaskContent(
            id: taskID,
            title: creationDraft.title.trimmingCharacters(in: .whitespacesAndNewlines),
            prompt: creationDraft.prompt,
            autoCreatePR: creationDraft.autoCreatePR
        )
        try load()
        return task
    }

    public func sendPreview(taskID: UUID) throws -> CursorSendPreview {
        guard let task = try store.task(id: taskID),
              let repository = try store.repository(id: task.repositoryID) else {
            throw CursorOperatorStoreError.taskNotFound
        }
        return try CursorSendPreview(task: task, repository: repository)
    }

    public func send(taskID: UUID) async throws {
        let service = CursorTaskSendService(
            store: store,
            credentialReadiness: CursorSendReadiness(provider: credentialProvider),
            runtime: runtime
        )
        _ = try await service.send(taskID: taskID)
        try load()
    }

    public func resumeRunMonitoring() async throws {
        let service = CursorRunMonitorService(
            store: store,
            credentialReadiness: CursorSendReadiness(provider: credentialProvider),
            runtime: runtime
        )
        _ = try await service.resumeRunningTasks()
        try load()
    }

    public func markDone(taskID: UUID) throws {
        _ = try store.markTaskDone(id: taskID)
        try load()
    }

    public func archive(taskID: UUID) throws {
        _ = try store.archiveTask(id: taskID)
        try load()
    }

    public func openInCursor(taskID: UUID) throws {
        guard let successfulAttempt = try store.runAttempts(taskID: taskID).last(where: { $0.status == .succeeded }) else {
            throw CursorOpenInCursorError.noCursorReference
        }

        let action: CursorExternalOpenAction
        if let cursorURL = successfulAttempt.cursorURL {
            action = .openURL(cursorURL)
        } else if let cursorRunID = successfulAttempt.cursorRunID {
            action = .copyRunID(cursorRunID)
        } else {
            action = .openDashboard(CursorCloudAgentDestinations.dashboard)
        }

        externalOpener.perform(action)
        errorMessage = nil
    }

    public func prepareRepositoryRegistration(at repositoryURL: URL) throws {
        pendingRepositoryDraft = try repositoryRegistrationService.prepareRepository(at: repositoryURL)
        errorMessage = nil
    }

    public func savePendingRepository(defaultBranch: String) throws {
        guard let pendingRepositoryDraft else {
            return
        }
        _ = try repositoryRegistrationService.saveRepository(
            pendingRepositoryDraft,
            defaultBranch: defaultBranch
        )
        self.pendingRepositoryDraft = nil
        try load()
    }

    public func loadReportingErrors() {
        do {
            try load()
        } catch {
            errorMessage = Self.userFacingMessage(for: error)
        }
    }

    public func createLocalTaskReportingErrors() {
        do {
            try createLocalTask(
                title: "Local Cursor task",
                prompt: "This local placeholder task proves the Cursor Operator SQLite lifecycle."
            )
        } catch {
            errorMessage = Self.userFacingMessage(for: error)
        }
    }

    public func createTaskFromDraftReportingErrors() -> Bool {
        do {
            _ = try createTaskFromDraft()
            return true
        } catch {
            errorMessage = Self.userFacingMessage(for: error)
            return false
        }
    }

    public func sendReportingErrors(taskID: UUID) {
        Task {
            do {
                try await send(taskID: taskID)
                resumeRunMonitoringReportingErrors()
            } catch CursorTaskSendError.missingCredentials {
                errorMessage = "Cursor API key is required before sending."
            } catch {
                errorMessage = Self.userFacingMessage(for: error)
            }
        }
    }

    public func resumeRunMonitoringReportingErrors() {
        Task {
            do {
                try await resumeRunMonitoring()
            } catch CursorTaskSendError.missingCredentials {
                errorMessage = "Cursor API key is required before monitoring runs."
            } catch {
                errorMessage = Self.userFacingMessage(for: error)
            }
        }
    }

    public func markDoneReportingErrors(taskID: UUID) {
        do {
            try markDone(taskID: taskID)
        } catch {
            errorMessage = Self.userFacingMessage(for: error)
        }
    }

    public func archiveReportingErrors(taskID: UUID) {
        do {
            try archive(taskID: taskID)
        } catch {
            errorMessage = Self.userFacingMessage(for: error)
        }
    }

    public func openInCursorReportingErrors(taskID: UUID) {
        do {
            try openInCursor(taskID: taskID)
        } catch {
            errorMessage = Self.userFacingMessage(for: error)
        }
    }

    public func prepareRepositoryRegistrationReportingErrors(at repositoryURL: URL) {
        do {
            try prepareRepositoryRegistration(at: repositoryURL)
        } catch {
            errorMessage = Self.userFacingMessage(for: error)
        }
    }

    public func savePendingRepositoryReportingErrors(defaultBranch: String) {
        do {
            try savePendingRepository(defaultBranch: defaultBranch)
        } catch {
            errorMessage = Self.userFacingMessage(for: error)
        }
    }

    private func firstRepositoryOrCreatePlaceholder() throws -> CursorRepository {
        if let repository = try store.repositories().first {
            return repository
        }

        return try store.createRepository(
            name: "Local Cursor Repository",
            localPath: FileManager.default.temporaryDirectory
                .appending(path: "cursor-operator-placeholder", directoryHint: .isDirectory)
                .path,
            githubURL: URL(string: "https://github.com/local/cursor-operator-placeholder")!,
            defaultBranch: "main"
        )
    }

    private static func userFacingMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let errorDescription = localizedError.errorDescription {
            return errorDescription
        }
        return "Cursor Operator could not update the board."
    }
}
