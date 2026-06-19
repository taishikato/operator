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
        credentialProvider: CursorCredentialProvider(store: InMemoryCursorCredentialStore(), environment: [:])
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
        )
    )

    try readyModel.load()
    #expect(readyModel.setupStatus.repositoryState == .registered(count: 1))
    #expect(readyModel.setupStatus.credentialState == .ready)
    #expect(readyModel.setupStatus.canSend)
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
