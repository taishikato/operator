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

private struct BoardModelStubRepositoryInspector: CursorRepositoryInspecting {
    let inspection: CursorRepositoryInspection

    func inspect(_ repositoryURL: URL) throws -> CursorRepositoryInspection {
        inspection
    }
}

private func temporaryBoardModelDatabaseURL() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "CursorBoardModelTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appending(path: "cursor-operator.sqlite")
}
