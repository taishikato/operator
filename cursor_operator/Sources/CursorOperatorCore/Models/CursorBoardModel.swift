import Combine
import Foundation

@MainActor
public final class CursorBoardModel: ObservableObject {
    @Published public private(set) var projection: CursorBoardProjection
    @Published public private(set) var repositories: [CursorRepository]
    @Published public private(set) var setupStatus: CursorSetupStatusProjection
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var pendingRepositoryDraft: CursorRepositoryRegistrationDraft?
    @Published public private(set) var editingTaskID: UUID?
    @Published public private(set) var sendingTaskIDs: Set<UUID>
    @Published public var creationDraft: CursorTaskCreationDraft

    private let store: CursorOperatorStore
    private let repositoryRegistrationService: CursorRepositoryRegistrationService
    private let credentialProvider: CursorCredentialProvider
    private let nodeResolver: any CursorNodeResolving
    private let settings: OperatorSettingsManager
    private let codexBinarySettings: any CodexBinarySettingsProviding
    private let codexStatusChecker: any CodexStatusChecking
    private let runtime: any CursorCloudAgentRuntime
    private let externalOpener: any CursorExternalOpening
    private let codexAppOpener: any CodexAppOpening
    private let codexTaskSender: (any CodexTaskSending)?
    private let codexRunRecoverer: (any CodexRunRecovering)?
    private var cancellables: Set<AnyCancellable>
    private var cachedNodeState: CursorNodeSetupState?
    private var codexStatus: CodexStatus

    public init(
        store: CursorOperatorStore,
        repositoryInspector: any CursorRepositoryInspecting = CursorGitRepositoryInspector(),
        credentialProvider: CursorCredentialProvider = CursorCredentialProvider(store: KeychainCursorCredentialStore()),
        nodeResolver: any CursorNodeResolving = CursorNodeExecutableResolver(),
        settings: OperatorSettingsManager = OperatorSettingsManager(),
        codexBinarySettings: any CodexBinarySettingsProviding = CodexBinarySettings(),
        codexStatusChecker: any CodexStatusChecking = CodexStatusChecker(),
        runtime: any CursorCloudAgentRuntime = CursorCloudAgentSDKRuntime(),
        externalOpener: any CursorExternalOpening = SystemCursorExternalOpener(),
        codexAppOpener: any CodexAppOpening = OSCodexAppOpener(),
        codexTaskSender: (any CodexTaskSending)? = nil,
        codexRunRecoverer: (any CodexRunRecovering)? = nil
    ) {
        self.store = store
        self.credentialProvider = credentialProvider
        self.nodeResolver = nodeResolver
        self.settings = settings
        self.codexBinarySettings = codexBinarySettings
        self.codexStatusChecker = codexStatusChecker
        self.runtime = runtime
        self.externalOpener = externalOpener
        self.codexAppOpener = codexAppOpener
        self.codexTaskSender = codexTaskSender
        self.codexRunRecoverer = codexRunRecoverer
        cancellables = []
        codexStatus = .notChecked
        repositoryRegistrationService = CursorRepositoryRegistrationService(
            store: store,
            inspector: repositoryInspector
        )
        projection = CursorBoardProjection(tasks: [])
        repositories = []
        setupStatus = .empty
        editingTaskID = nil
        sendingTaskIDs = []
        creationDraft = CursorTaskCreationDraft(harness: settings.defaultHarness())
        NotificationCenter.default.publisher(for: .cursorOperatorRunsChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.loadReportingErrors()
            }
            .store(in: &cancellables)
    }

    public func load() throws {
        repositories = try store.repositories()
        setupStatus = try CursorSetupStatusProjection(
            repositoryState: repositories.isEmpty ? .missing : .registered(count: repositories.count),
            credentialState: CursorSendReadiness(provider: credentialProvider).credentialState(),
            nodeState: nodeSetupState(),
            codexState: codexSetupState(),
            selectedHarness: creationDraft.harness
        )
        projection = try CursorBoardProjection.load(from: store)
        errorMessage = nil
    }

    public func checkCodexStatus() async throws {
        let configuration = try codexBinarySettings.configuration()
        codexStatus = await codexStatusChecker.checkStatus(binaryURL: configuration.effectiveBinaryURL)
        try load()
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
        creationDraft = CursorTaskCreationDraft(
            repositoryID: creationDraft.repositoryID,
            harness: settings.defaultHarness()
        )
        editingTaskID = nil
        try load()
        return task
    }

    public func prepareCreateTaskDraftForPresentation() -> Bool {
        editingTaskID = nil
        creationDraft.repositoryID = creationDraft.repositoryID ?? repositories.first?.id
        // Reset only autoSend: it triggers an immediate send, so a stale opt-in
        // must never carry into a new task. Typed content (title/prompt/
        // autoCreatePR) is preserved so an accidental cancel does not discard an
        // in-progress draft.
        creationDraft.autoSend = false
        guard creationDraft.repositoryID != nil else {
            errorMessage = "Register a repository before creating a task."
            return false
        }
        return true
    }

    public func prepareEditTaskDraftForPresentation(taskID: UUID) -> Bool {
        do {
            guard let task = try store.task(id: taskID) else {
                throw CursorOperatorStoreError.taskNotFound
            }
            try CursorTaskLifecyclePolicy.ensureEditable(task)
            creationDraft = CursorTaskCreationDraft(
                repositoryID: task.repositoryID,
                title: task.title,
                prompt: task.prompt,
                autoCreatePR: task.autoCreatePR,
                reasoningEffort: task.reasoningEffort,
                useFastModel: task.useFastModel,
                harness: task.harness
            )
            editingTaskID = task.id
            errorMessage = nil
            return true
        } catch {
            errorMessage = Self.userFacingMessage(for: error)
            return false
        }
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
            autoCreatePR: creationDraft.autoCreatePR,
            reasoningEffort: creationDraft.reasoningEffort,
            useFastModel: creationDraft.useFastModel,
            harness: creationDraft.harness
        )
        creationDraft = CursorTaskCreationDraft(
            repositoryID: creationDraft.repositoryID,
            harness: settings.defaultHarness()
        )
        editingTaskID = nil
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

    public func isSending(taskID: UUID) -> Bool {
        sendingTaskIDs.contains(taskID)
    }

    public func sendStatusText(taskID: UUID) -> String? {
        isSending(taskID: taskID) ? "Sending to Cursor..." : nil
    }

    public func send(taskID: UUID) async throws {
        guard let task = try store.task(id: taskID) else {
            throw CursorOperatorStoreError.taskNotFound
        }
        let attempt: OperatorRun
        switch task.harness {
        case .cursor:
            let service = CursorTaskSendService(
                store: store,
                credentialReadiness: CursorSendReadiness(provider: credentialProvider),
                runtime: runtime
            )
            attempt = try await service.send(taskID: taskID)
        case .codex:
            let sender = codexTaskSender ?? productionCodexTaskSender()
            attempt = try await sender.sendTaskToCodex(taskID: taskID)
        case .claudeCode:
            throw CursorTaskSendError.unsupportedHarness(task.harness)
        }
        // Reload before surfacing a failure so the board projection reflects the
        // recorded failed attempt (the per-card failed-send indicator), not just
        // the transient global error message.
        try load()
        guard attempt.status != .failed else {
            throw CursorTaskSendError.sendFailed(
                message: attempt.errorMessage ?? "\(task.harness.displayName) did not start the run."
            )
        }
    }

    private func productionCodexTaskSender() -> any CodexTaskSending {
        productionCodexTriggerService()
    }

    private func productionCodexTriggerService() -> CodexTriggerService {
        CodexTriggerService(
            store: store,
            worktreePreparer: WorktreePreparer(),
            appServerClientFactory: ConfiguredCodexAppServerClientFactory(settings: codexBinarySettings),
            threadVisibility: CodexCLIThreadVisibilityController(settings: codexBinarySettings)
        )
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

    public func recoverForRetry(taskID: UUID) throws {
        _ = try store.recoverTaskForRetry(id: taskID)
        try load()
    }

    public func openInCursor(taskID: UUID) throws {
        guard let successfulAttempt = try store.runAttempts(taskID: taskID).last(where: { $0.status == .succeeded && $0.harness == .cursor }) else {
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

    public func openInCodex(taskID: UUID) throws {
        guard let successfulAttempt = try store.runAttempts(taskID: taskID).last(where: { $0.status == .succeeded && $0.harness == .codex }),
              let target = CodexOpenTarget(run: successfulAttempt) else {
            throw CodexOpenInCodexError.noCodexReference
        }

        try codexAppOpener.open(target)
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

    /// Re-fetch the board: reload the local projection and re-attach run
    /// monitoring so running tasks pick up any remote status changes. This is
    /// the same work performed when the board first appears.
    public func refreshReportingErrors() {
        loadReportingErrors()
        recoverInterruptedCodexRunsReportingErrors()
        resumeRunMonitoringReportingErrors()
    }

    public func createLocalTaskReportingErrors() {
        do {
            try createLocalTask(
                title: "Local Cursor task",
                prompt: "This local placeholder task proves the Operator SQLite lifecycle."
            )
        } catch {
            errorMessage = Self.userFacingMessage(for: error)
        }
    }

    public func createTaskFromDraftReportingErrors() -> Bool {
        do {
            let shouldAutoSend = creationDraft.autoSend && setupStatus.canSend
            let task = try createTaskFromDraft()
            if shouldAutoSend {
                sendReportingErrors(taskID: task.id)
            }
            return true
        } catch {
            errorMessage = Self.userFacingMessage(for: error)
            return false
        }
    }

    public func updateEditingTaskFromDraftReportingErrors() -> Bool {
        guard let editingTaskID else {
            errorMessage = "Choose a task before saving changes."
            return false
        }

        do {
            _ = try updateTaskFromDraft(taskID: editingTaskID)
            return true
        } catch {
            errorMessage = Self.userFacingMessage(for: error)
            return false
        }
    }

    public func saveTaskDraftReportingErrors() -> Bool {
        if editingTaskID != nil {
            updateEditingTaskFromDraftReportingErrors()
        } else {
            createTaskFromDraftReportingErrors()
        }
    }

    public func sendReportingErrors(taskID: UUID) {
        guard !sendingTaskIDs.contains(taskID) else {
            return
        }
        sendingTaskIDs.insert(taskID)
        Task {
            defer {
                sendingTaskIDs.remove(taskID)
            }
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

    public func recoverInterruptedCodexRunsReportingErrors() {
        Task {
            let recoverer = codexRunRecoverer ?? productionCodexTriggerService()
            await recoverer.recoverInterruptedRuns()
            loadReportingErrors()
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

    public func recoverForRetryReportingErrors(taskID: UUID) {
        do {
            try recoverForRetry(taskID: taskID)
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

    public func openInCodexReportingErrors(taskID: UUID) {
        do {
            try openInCodex(taskID: taskID)
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
                .appending(path: "operator-placeholder", directoryHint: .isDirectory)
                .path,
            githubURL: URL(string: "https://github.com/local/operator-placeholder")!,
            defaultBranch: "main"
        )
    }

    private func nodeSetupState() -> CursorNodeSetupState {
        // Resolving Node spawns a subprocess (`node --version`); cache only
        // successful detection so missing Node can recover after installation.
        if let cachedNodeState {
            return cachedNodeState
        }
        let state: CursorNodeSetupState
        do {
            let resolution = try nodeResolver.resolve()
            state = .ready(version: resolution.version)
            cachedNodeState = state
        } catch {
            state = .missing
        }
        return state
    }

    private func codexSetupState() -> CodexSetupState {
        switch codexStatus {
        case .notChecked:
            .notChecked
        case let .ready(binaryURL):
            .ready(binaryPath: binaryURL.path)
        case .notFound:
            .notFound
        case let .notAuthenticatedOrUnavailable(message):
            .unavailable(message)
        }
    }

    private static func userFacingMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let errorDescription = localizedError.errorDescription {
            return errorDescription
        }
        return "Operator could not update the board."
    }
}
