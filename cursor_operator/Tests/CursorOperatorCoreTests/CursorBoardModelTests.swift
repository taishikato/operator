import Foundation
import Testing
@testable import CursorOperatorCore

@MainActor
@Test func boardModelCreatesLocalPlaceholderTaskForMVPDemo() throws {
    let store = try CursorOperatorStore(databaseURL: temporaryBoardModelDatabaseURL())
    let model = CursorBoardModel(store: store)

    try model.createLocalTask(title: "Local task", prompt: "Use the local store")

    #expect(model.projection.columns.flatMap(\.cards).map(\.title) == ["Local task"])
    #expect(try store.repositories().first?.name == "Local Cursor Repository")
}

@MainActor
@Test func boardModelReportsRepositoryAndCredentialSetupStatus() throws {
    let store = try CursorOperatorStore(databaseURL: temporaryBoardModelDatabaseURL())
    let missingCredentialModel = CursorBoardModel(
        store: store,
        credentialProvider: CursorCredentialProvider(store: InMemoryCursorCredentialStore(), environment: [:]),
        nodeResolver: CompatibleBoardModelNodeResolver()
    )

    try missingCredentialModel.load()
    #expect(missingCredentialModel.setupStatus.repositoryState == .missing)
    #expect(missingCredentialModel.setupStatus.credentialState == .missing)
    #expect(missingCredentialModel.setupStatus.canSend == false)

    _ = try store.createRepository(
        name: "operator",
        localPath: "/tmp/operator",
        githubURL: URL(string: "https://github.com/example/operator")!,
        defaultBranch: "main"
    )
    let readyModel = CursorBoardModel(
        store: store,
        credentialProvider: CursorCredentialProvider(
            store: InMemoryCursorCredentialStore(apiKey: "crsr_test_key"),
            environment: [:]
        ),
        nodeResolver: CompatibleBoardModelNodeResolver()
    )

    try readyModel.load()
    #expect(readyModel.setupStatus.repositoryState == .registered(count: 1))
    #expect(readyModel.setupStatus.credentialState == .ready)
    #expect(readyModel.setupStatus.nodeState == .ready(version: "v22.13.0"))
    #expect(readyModel.setupStatus.canSend)
}

@MainActor
@Test func boardModelBlocksSendReadinessWhenNodeIsMissing() throws {
    let store = try CursorOperatorStore(databaseURL: temporaryBoardModelDatabaseURL())
    _ = try store.createRepository(
        name: "operator",
        localPath: "/tmp/operator",
        githubURL: URL(string: "https://github.com/example/operator")!,
        defaultBranch: "main"
    )
    let model = CursorBoardModel(
        store: store,
        credentialProvider: CursorCredentialProvider(
            store: InMemoryCursorCredentialStore(apiKey: "crsr_test_key"),
            environment: [:]
        ),
        nodeResolver: MissingBoardModelNodeResolver()
    )

    try model.load()

    #expect(model.setupStatus.nodeState == .missing)
    #expect(model.setupStatus.nodeMessage == "Node.js: 22.13+ required")
    #expect(model.setupStatus.canSend == false)
}

@MainActor
@Test func boardModelRechecksMissingNodeOnNextLoad() throws {
    let store = try CursorOperatorStore(databaseURL: temporaryBoardModelDatabaseURL())
    _ = try store.createRepository(
        name: "operator",
        localPath: "/tmp/operator",
        githubURL: URL(string: "https://github.com/example/operator")!,
        defaultBranch: "main"
    )
    let nodeResolver = RecoveringBoardModelNodeResolver()
    let model = CursorBoardModel(
        store: store,
        credentialProvider: CursorCredentialProvider(
            store: InMemoryCursorCredentialStore(apiKey: "crsr_test_key"),
            environment: [:]
        ),
        nodeResolver: nodeResolver
    )

    try model.load()
    #expect(model.setupStatus.nodeState == .missing)

    nodeResolver.isReady = true
    try model.load()

    #expect(model.setupStatus.nodeState == .ready(version: "v22.13.0"))
    #expect(model.setupStatus.canSend)
}

@MainActor
@Test func boardModelMovesRunningTasksToDoneAndArchivesActiveTasks() throws {
    let store = try CursorOperatorStore(databaseURL: temporaryBoardModelDatabaseURL())
    let repository = try store.createRepository(
        name: "operator",
        localPath: "/tmp/operator",
        githubURL: URL(string: "https://github.com/example/operator")!,
        defaultBranch: "main"
    )
    let task = try store.createTask(repositoryID: repository.id, title: "Finish", prompt: "Prompt")
    _ = try store.recordSuccessfulSendAttempt(
        taskID: task.id,
        repositoryURL: repository.githubURL,
        startingRef: repository.defaultBranch,
        model: CursorModel.fixed,
        autoCreatePR: false,
        prompt: task.prompt,
        cursorAgentID: "agent-123",
        cursorRunID: "run-123",
        cursorURL: URL(string: "https://cursor.com/agents/agent-123")!
    )
    let model = CursorBoardModel(store: store)
    try model.load()

    try model.markDone(taskID: task.id)
    #expect(try store.task(id: task.id)?.status == .done)

    try model.archive(taskID: task.id)
    #expect(try store.task(id: task.id)?.status == .archived)
    #expect(model.projection.columns.flatMap(\.cards).isEmpty)
}

@MainActor
@Test func boardModelOpensCursorURLAndCopiesRunIDFallback() throws {
    let store = try CursorOperatorStore(databaseURL: temporaryBoardModelDatabaseURL())
    let repository = try store.createRepository(
        name: "operator",
        localPath: "/tmp/operator",
        githubURL: URL(string: "https://github.com/example/operator")!,
        defaultBranch: "main"
    )
    let urlTask = try store.createTask(repositoryID: repository.id, title: "Open URL", prompt: "Prompt")
    _ = try store.recordSuccessfulSendAttempt(
        taskID: urlTask.id,
        repositoryURL: repository.githubURL,
        startingRef: repository.defaultBranch,
        model: CursorModel.fixed,
        autoCreatePR: false,
        prompt: urlTask.prompt,
        cursorAgentID: "agent-url",
        cursorRunID: "run-url",
        cursorURL: URL(string: "https://cursor.com/agents/agent-url")!
    )
    let fallbackTask = try store.createTask(repositoryID: repository.id, title: "Copy run", prompt: "Prompt")
    _ = try store.recordSuccessfulSendAttempt(
        taskID: fallbackTask.id,
        repositoryURL: repository.githubURL,
        startingRef: repository.defaultBranch,
        model: CursorModel.fixed,
        autoCreatePR: false,
        prompt: fallbackTask.prompt,
        cursorAgentID: "agent-copy",
        cursorRunID: "run-copy",
        cursorURL: nil
    )
    let opener = BoardModelFakeExternalOpener()
    let model = CursorBoardModel(store: store, externalOpener: opener)

    try model.openInCursor(taskID: urlTask.id)
    try model.openInCursor(taskID: fallbackTask.id)

    #expect(opener.actions == [
        .openURL(URL(string: "https://cursor.com/agents/agent-url")!),
        .copyRunID("run-copy")
    ])
}

@MainActor
@Test func boardModelManualDoneDoesNotStartCursorRuntime() throws {
    let store = try CursorOperatorStore(databaseURL: temporaryBoardModelDatabaseURL())
    let repository = try store.createRepository(
        name: "operator",
        localPath: "/tmp/operator",
        githubURL: URL(string: "https://github.com/example/operator")!,
        defaultBranch: "main"
    )
    let task = try store.createTask(repositoryID: repository.id, title: "Manual", prompt: "Prompt")
    _ = try store.recordSuccessfulSendAttempt(
        taskID: task.id,
        repositoryURL: repository.githubURL,
        startingRef: repository.defaultBranch,
        model: CursorModel.fixed,
        autoCreatePR: false,
        prompt: task.prompt,
        cursorAgentID: "agent-manual",
        cursorRunID: "run-manual",
        cursorURL: URL(string: "https://cursor.com/agents/agent-manual")!
    )
    let runtime = BoardModelFakeRuntime(reference: CursorCloudAgentReference(
        agentID: "unused",
        runID: "unused",
        openURL: URL(string: "https://cursor.com/agents/unused")!
    ))
    let model = CursorBoardModel(store: store, runtime: runtime)
    try model.load()

    try model.markDone(taskID: task.id)

    #expect(try store.task(id: task.id)?.status == .done)
    #expect(runtime.requests.isEmpty)
}

@MainActor
@Test func boardModelPreparesAndSavesReviewedRepositoryRegistration() throws {
    let store = try CursorOperatorStore(databaseURL: temporaryBoardModelDatabaseURL())
    let repositoryURL = URL(filePath: "/tmp/operator")
    let inspector = BoardModelStubRepositoryInspector(
        inspection: CursorRepositoryInspection(
            name: "operator",
            localPath: repositoryURL.path,
            githubURL: URL(string: "https://github.com/example/operator")!,
            defaultBranch: "main"
        )
    )
    let model = CursorBoardModel(store: store, repositoryInspector: inspector)

    try model.prepareRepositoryRegistration(at: repositoryURL)
    #expect(model.pendingRepositoryDraft?.defaultBranch == "main")

    try model.savePendingRepository(defaultBranch: "trunk")

    #expect(model.pendingRepositoryDraft == nil)
    #expect(try store.repositories().first?.defaultBranch == "trunk")
}

@MainActor
@Test func boardModelCreatesReadyTaskFromDraftAndBuildsSendPreview() throws {
    let store = try CursorOperatorStore(databaseURL: temporaryBoardModelDatabaseURL())
    let repository = try store.createRepository(
        name: "operator",
        localPath: "/tmp/operator",
        githubURL: URL(string: "https://github.com/example/operator")!,
        defaultBranch: "main"
    )
    let model = CursorBoardModel(store: store)
    model.creationDraft = CursorTaskCreationDraft(
        repositoryID: repository.id,
        title: "Preview task",
        prompt: "Prompt exactly",
        autoCreatePR: true
    )

    let task = try model.createTaskFromDraft()
    let preview = try model.sendPreview(taskID: task.id)

    #expect(task.autoCreatePR)
    #expect(preview.repositoryURL == repository.githubURL)
    #expect(preview.startingRef == "main")
    #expect(preview.model == CursorModel.fixed)
    #expect(preview.prompt == "Prompt exactly")
}

@MainActor
@Test func boardModelAutoSendsNewTaskFromDraftWhenRequested() async throws {
    let store = try CursorOperatorStore(databaseURL: temporaryBoardModelDatabaseURL())
    let repository = try store.createRepository(
        name: "operator",
        localPath: "/tmp/operator",
        githubURL: URL(string: "https://github.com/example/operator")!,
        defaultBranch: "main"
    )
    let runtime = BoardModelFakeRuntime(reference: CursorCloudAgentReference(
        agentID: "agent-auto-send",
        runID: "run-auto-send",
        openURL: URL(string: "https://cursor.com/agents/agent-auto-send")!
    ))
    let model = CursorBoardModel(
        store: store,
        credentialProvider: CursorCredentialProvider(
            store: InMemoryCursorCredentialStore(apiKey: "crsr_test_key"),
            environment: [:]
        ),
        nodeResolver: CompatibleBoardModelNodeResolver(),
        runtime: runtime
    )
    try model.load()
    model.creationDraft = CursorTaskCreationDraft(
        repositoryID: repository.id,
        title: "Auto send",
        prompt: "Prompt",
        autoCreatePR: true,
        autoSend: true
    )

    #expect(model.createTaskFromDraftReportingErrors())
    try await waitUntil {
        try store.tasks().first?.status == .running
    }

    #expect(runtime.requests.count == 1)
    #expect(runtime.requests.first?.autoCreatePR == true)
    #expect(model.creationDraft.autoSend == false)
}

@MainActor
@Test func boardModelDoesNotAutoSendWhenCanSendIsFalse() async throws {
    let store = try CursorOperatorStore(databaseURL: temporaryBoardModelDatabaseURL())
    let repository = try store.createRepository(
        name: "operator",
        localPath: "/tmp/operator",
        githubURL: URL(string: "https://github.com/example/operator")!,
        defaultBranch: "main"
    )
    let runtime = BoardModelFakeRuntime(reference: CursorCloudAgentReference(
        agentID: "agent-auto-send",
        runID: "run-auto-send",
        openURL: URL(string: "https://cursor.com/agents/agent-auto-send")!
    ))
    let model = CursorBoardModel(
        store: store,
        credentialProvider: CursorCredentialProvider(store: InMemoryCursorCredentialStore(), environment: [:]),
        nodeResolver: MissingBoardModelNodeResolver(),
        runtime: runtime
    )
    try model.load()
    model.creationDraft = CursorTaskCreationDraft(
        repositoryID: repository.id,
        title: "Auto send blocked",
        prompt: "Prompt",
        autoSend: true
    )

    #expect(model.setupStatus.canSend == false)
    #expect(model.createTaskFromDraftReportingErrors())
    try await Task.sleep(nanoseconds: 50_000_000)

    #expect(try store.tasks().first?.status == .ready)
    #expect(runtime.requests.isEmpty)
}

@MainActor
@Test func boardModelResetsAutoSendWhenPresentingCreateDraft() throws {
    let store = try CursorOperatorStore(databaseURL: temporaryBoardModelDatabaseURL())
    let repository = try store.createRepository(
        name: "operator",
        localPath: "/tmp/operator",
        githubURL: URL(string: "https://github.com/example/operator")!,
        defaultBranch: "main"
    )
    let model = CursorBoardModel(
        store: store,
        credentialProvider: CursorCredentialProvider(
            store: InMemoryCursorCredentialStore(apiKey: "crsr_test_key"),
            environment: [:]
        ),
        nodeResolver: CompatibleBoardModelNodeResolver()
    )
    try model.load()
    model.creationDraft.autoSend = true

    #expect(model.prepareCreateTaskDraftForPresentation())
    #expect(model.creationDraft.autoSend == false)
    #expect(model.creationDraft.repositoryID == repository.id)
}

@MainActor
@Test func boardModelSendReportingErrorsSurfacesRuntimeFailure() async throws {
    let store = try CursorOperatorStore(databaseURL: temporaryBoardModelDatabaseURL())
    let repository = try store.createRepository(
        name: "operator",
        localPath: "/tmp/operator",
        githubURL: URL(string: "https://github.com/example/operator")!,
        defaultBranch: "main"
    )
    let task = try store.createTask(repositoryID: repository.id, title: "Send", prompt: "Prompt")
    let runtime = BoardModelFailingRuntime(message: "Cursor rejected the run request.")
    let model = CursorBoardModel(
        store: store,
        credentialProvider: CursorCredentialProvider(
            store: InMemoryCursorCredentialStore(apiKey: "crsr_test_key"),
            environment: [:]
        ),
        // Inject a deterministic node resolver so the reload on the failure path
        // does not spawn a `node --version` subprocess, which made the timed
        // wait below flaky under parallel test load.
        nodeResolver: CompatibleBoardModelNodeResolver(),
        runtime: runtime
    )
    try model.load()

    model.sendReportingErrors(taskID: task.id)
    try await waitUntil {
        model.errorMessage != nil
    }

    #expect(model.errorMessage == "Cursor send failed: Cursor rejected the run request.")
    #expect(try store.task(id: task.id)?.status == .ready)

    // The projection must refresh on failure so the card shows the persistent
    // failed-send indicator, not just the transient global error message.
    let readyCard = try #require(model.projection.columns.first { $0.id == .ready }?.cards.first)
    #expect(readyCard.failedSendMessage == "Cursor rejected the run request.")
}

@MainActor
@Test func boardModelPreparesReadyTaskDraftForEditingAndUpdatesIt() throws {
    let store = try CursorOperatorStore(databaseURL: temporaryBoardModelDatabaseURL())
    let repository = try store.createRepository(
        name: "operator",
        localPath: "/tmp/operator",
        githubURL: URL(string: "https://github.com/example/operator")!,
        defaultBranch: "main"
    )
    let task = try store.createTask(
        repositoryID: repository.id,
        title: "Original",
        prompt: "Original prompt",
        autoCreatePR: false
    )
    let model = CursorBoardModel(store: store)

    #expect(model.prepareEditTaskDraftForPresentation(taskID: task.id))
    #expect(model.editingTaskID == task.id)
    #expect(model.creationDraft == CursorTaskCreationDraft(
        repositoryID: repository.id,
        title: "Original",
        prompt: "Original prompt",
        autoCreatePR: false
    ))

    model.creationDraft.title = "Edited"
    model.creationDraft.prompt = "Edited prompt"
    model.creationDraft.autoCreatePR = true
    #expect(model.saveTaskDraftReportingErrors())

    let updated = try #require(try store.task(id: task.id))
    #expect(updated.title == "Edited")
    #expect(updated.prompt == "Edited prompt")
    #expect(updated.autoCreatePR)
    #expect(model.editingTaskID == nil)
}

@MainActor
@Test func boardModelSendsReadyTaskWithInjectedRuntime() async throws {
    let store = try CursorOperatorStore(databaseURL: temporaryBoardModelDatabaseURL())
    let repository = try store.createRepository(
        name: "operator",
        localPath: "/tmp/operator",
        githubURL: URL(string: "https://github.com/example/operator")!,
        defaultBranch: "main"
    )
    let task = try store.createTask(repositoryID: repository.id, title: "Send", prompt: "Prompt")
    let runtime = BoardModelFakeRuntime(reference: CursorCloudAgentReference(
        agentID: "agent-board",
        runID: "run-board",
        openURL: URL(string: "https://cursor.com/agents/agent-board")!
    ))
    let model = CursorBoardModel(
        store: store,
        credentialProvider: CursorCredentialProvider(
            store: InMemoryCursorCredentialStore(apiKey: "crsr_test_key"),
            environment: [:]
        ),
        runtime: runtime
    )
    try model.load()

    try await model.send(taskID: task.id)

    #expect(try store.task(id: task.id)?.status == .running)
    #expect(runtime.requests.count == 1)
}

@MainActor
@Test func boardModelIgnoresDuplicateSendReportsWhileTaskIsAlreadySending() async throws {
    let store = try CursorOperatorStore(databaseURL: temporaryBoardModelDatabaseURL())
    let repository = try store.createRepository(
        name: "operator",
        localPath: "/tmp/operator",
        githubURL: URL(string: "https://github.com/example/operator")!,
        defaultBranch: "main"
    )
    let task = try store.createTask(repositoryID: repository.id, title: "Send once", prompt: "Prompt")
    let runtime = BoardModelSuspendingRuntime(reference: CursorCloudAgentReference(
        agentID: "agent-board",
        runID: "run-board",
        openURL: URL(string: "https://cursor.com/agents/agent-board")!
    ))
    let model = CursorBoardModel(
        store: store,
        credentialProvider: CursorCredentialProvider(
            store: InMemoryCursorCredentialStore(apiKey: "crsr_test_key"),
            environment: [:]
        ),
        runtime: runtime
    )
    try model.load()

    model.sendReportingErrors(taskID: task.id)
    try await runtime.waitUntilStarted()
    #expect(model.isSending(taskID: task.id))
    #expect(model.sendStatusText(taskID: task.id) == "Sending to Cursor...")

    model.sendReportingErrors(taskID: task.id)
    try await Task.sleep(nanoseconds: 20_000_000)

    #expect(model.errorMessage == nil)
    #expect(runtime.startCount == 1)

    runtime.complete()
    try await waitUntil {
        try store.task(id: task.id)?.status == .running && !model.isSending(taskID: task.id)
    }
    #expect(model.isSending(taskID: task.id) == false)
    #expect(model.sendStatusText(taskID: task.id) == nil)
}

@Test func lifecycleErrorsHaveUserFacingDescriptions() {
    #expect(localizedDescription(for: CursorTaskLifecycleError.taskAlreadyHasSuccessfulRun) == "This task is already being sent or already has a Cursor run.")
    #expect(localizedDescription(for: CursorTaskLifecycleError.transitionNotAllowed) == "This task cannot be moved to that state.")
    #expect(localizedDescription(for: CursorTaskLifecycleError.taskIsImmutable) == "This task can no longer be edited.")
    #expect(localizedDescription(for: CursorTaskLifecycleError.hardDeleteNotAllowed) == "Tasks can be archived, but not permanently deleted.")
}

@MainActor
@Test func boardModelCanResumeMonitoringAndMoveCompletedRunDone() async throws {
    let store = try CursorOperatorStore(databaseURL: temporaryBoardModelDatabaseURL())
    let repository = try store.createRepository(
        name: "operator",
        localPath: "/tmp/operator",
        githubURL: URL(string: "https://github.com/example/operator")!,
        defaultBranch: "main"
    )
    let task = try store.createTask(repositoryID: repository.id, title: "Resume", prompt: "Prompt")
    _ = try store.recordSuccessfulSendAttempt(
        taskID: task.id,
        repositoryURL: repository.githubURL,
        startingRef: repository.defaultBranch,
        model: CursorModel.fixed,
        autoCreatePR: false,
        prompt: task.prompt,
        cursorAgentID: "agent-resume",
        cursorRunID: "run-resume",
        cursorURL: URL(string: "https://cursor.com/agents/agent-resume")!
    )
    let runtime = BoardModelMonitoringRuntime(completion: CursorCloudAgentRunCompletion(
        status: "finished",
        result: "Complete"
    ))
    let model = CursorBoardModel(
        store: store,
        credentialProvider: CursorCredentialProvider(
            store: InMemoryCursorCredentialStore(apiKey: "crsr_test_key"),
            environment: [:]
        ),
        runtime: runtime
    )
    try model.load()

    try await model.resumeRunMonitoring()

    #expect(try store.task(id: task.id)?.status == .done)
    #expect(runtime.waits.map(\.runID) == ["run-resume"])
}

private struct BoardModelStubRepositoryInspector: CursorRepositoryInspecting {
    let inspection: CursorRepositoryInspection

    func inspect(_ repositoryURL: URL) throws -> CursorRepositoryInspection {
        inspection
    }
}

private final class BoardModelFakeRuntime: CursorCloudAgentRuntime, @unchecked Sendable {
    let reference: CursorCloudAgentReference
    private(set) var requests: [CursorCloudAgentRequestPreview] = []

    init(reference: CursorCloudAgentReference) {
        self.reference = reference
    }

    func startCloudAgent(request: CursorCloudAgentRequestPreview, apiKey: String) async throws -> CursorCloudAgentReference {
        requests.append(request)
        return reference
    }
}

private struct BoardModelFailingRuntime: CursorCloudAgentRuntime {
    let message: String

    func startCloudAgent(request: CursorCloudAgentRequestPreview, apiKey: String) async throws -> CursorCloudAgentReference {
        throw CursorRuntimeFailure(message: message)
    }
}

private final class BoardModelSuspendingRuntime: CursorCloudAgentRuntime, @unchecked Sendable {
    let reference: CursorCloudAgentReference
    private let lock = NSLock()
    private var starts = 0
    private var startContinuation: CheckedContinuation<Void, Never>?
    private var completionContinuation: CheckedContinuation<Void, Never>?

    var startCount: Int {
        lock.withLock { starts }
    }

    init(reference: CursorCloudAgentReference) {
        self.reference = reference
    }

    func startCloudAgent(request: CursorCloudAgentRequestPreview, apiKey: String) async throws -> CursorCloudAgentReference {
        lock.withLock {
            starts += 1
            startContinuation?.resume()
            startContinuation = nil
        }
        await withCheckedContinuation { continuation in
            lock.withLock {
                completionContinuation = continuation
            }
        }
        return reference
    }

    func waitUntilStarted() async throws {
        if startCount > 0 {
            return
        }
        await withCheckedContinuation { continuation in
            lock.withLock {
                startContinuation = continuation
            }
        }
    }

    func complete() {
        lock.withLock {
            completionContinuation?.resume()
            completionContinuation = nil
        }
    }
}

private final class BoardModelMonitoringRuntime: CursorCloudAgentRuntime, @unchecked Sendable {
    let completion: CursorCloudAgentRunCompletion
    private(set) var waits: [CursorCloudAgentReference] = []

    init(completion: CursorCloudAgentRunCompletion) {
        self.completion = completion
    }

    func startCloudAgent(request: CursorCloudAgentRequestPreview, apiKey: String) async throws -> CursorCloudAgentReference {
        CursorCloudAgentReference(
            agentID: "agent-board-monitor",
            runID: "run-board-monitor",
            openURL: URL(string: "https://cursor.com/agents/agent-board-monitor")!
        )
    }

    func waitForRun(reference: CursorCloudAgentReference, apiKey: String) async throws -> CursorCloudAgentRunCompletion {
        waits.append(reference)
        return completion
    }
}

private struct CompatibleBoardModelNodeResolver: CursorNodeResolving {
    func resolve() throws -> CursorNodeResolution {
        CursorNodeResolution(
            executableURL: URL(filePath: "/opt/homebrew/bin/node"),
            version: "v22.13.0"
        )
    }
}

private struct MissingBoardModelNodeResolver: CursorNodeResolving {
    func resolve() throws -> CursorNodeResolution {
        throw CursorNodeResolutionError.missingCompatibleNode
    }
}

private final class RecoveringBoardModelNodeResolver: CursorNodeResolving, @unchecked Sendable {
    var isReady = false

    func resolve() throws -> CursorNodeResolution {
        guard isReady else {
            throw CursorNodeResolutionError.missingCompatibleNode
        }
        return CursorNodeResolution(
            executableURL: URL(filePath: "/opt/homebrew/bin/node"),
            version: "v22.13.0"
        )
    }
}

@MainActor
private final class BoardModelFakeExternalOpener: CursorExternalOpening {
    private(set) var actions: [CursorExternalOpenAction] = []

    func perform(_ action: CursorExternalOpenAction) {
        actions.append(action)
    }
}

private func temporaryBoardModelDatabaseURL() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "CursorBoardModelTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appending(path: "cursor-operator.sqlite")
}

@MainActor
private func waitUntil(
    timeout: TimeInterval = 1,
    condition: @escaping () throws -> Bool
) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if try condition() {
            return
        }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    Issue.record("Timed out waiting for condition.")
}

private func localizedDescription(for error: Error) -> String? {
    (error as? LocalizedError)?.errorDescription
}
