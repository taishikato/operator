import Foundation
import Testing
@testable import OperatorDesktop

@Test func archivedTasksProjectionExposesOpenInCodexForArchivedTasksWithSuccessfulRuns() throws {
    let store = try OperatorStore(databaseURL: temporaryDatabaseURL())
    let repository = try store.createRepository(name: "operator", path: "/tmp/operator", defaultBranch: "main")
    let successfulTask = try store.createTask(repositoryID: repository.id, title: "Successful archive", prompt: "Prompt")
    let threadURL = URL(string: "codex://thread/archived")!
    _ = try store.recordSuccessfulRun(
        taskID: successfulTask.id,
        worktreePath: "/tmp/worktrees/archived-success",
        baseBranch: "main",
        baseRef: "abc123",
        codexThreadID: "thread-archived",
        codexThreadURL: threadURL
    )
    _ = try store.archiveTask(id: successfulTask.id)
    let readyArchivedTask = try store.createTask(repositoryID: repository.id, title: "Ready archive", prompt: "Prompt")
    _ = try store.archiveTask(id: readyArchivedTask.id)

    let projection = try ArchivedTasksProjection.load(from: store)

    #expect(projection.tasks.map(\.id) == [successfulTask.id, readyArchivedTask.id])
    #expect(projection.tasks[0].title == "Successful archive")
    #expect(projection.tasks[0].canOpenInCodexApp)
    #expect(projection.tasks[0].codexOpenLabel == "Open in Codex App")
    #expect(projection.tasks[0].codexOpenTarget == .url(threadURL))
    #expect(projection.tasks[1].title == "Ready archive")
    #expect(projection.tasks[1].canOpenInCodexApp == false)
    #expect(projection.tasks[1].codexOpenTarget == nil)
}

@Test @MainActor func archivedTasksModelOpensArchivedCodexTarget() throws {
    let store = try OperatorStore(databaseURL: temporaryDatabaseURL())
    let repository = try store.createRepository(name: "operator", path: "/tmp/operator", defaultBranch: "main")
    let task = try store.createTask(repositoryID: repository.id, title: "Archived", prompt: "Prompt")
    _ = try store.recordSuccessfulRun(
        taskID: task.id,
        worktreePath: "/tmp/worktrees/archived",
        baseBranch: "main",
        baseRef: "abc123",
        codexThreadID: "thread-archived",
        codexThreadURL: nil
    )
    _ = try store.archiveTask(id: task.id)
    let opener = RecordingArchivedCodexAppOpener()
    let model = ArchivedTasksModel(store: store, codexOpener: opener)
    try model.load()

    model.openTaskInCodexAppReportingErrors(taskID: task.id)

    #expect(opener.openedTargets == [.worktree(URL(filePath: "/tmp/worktrees/archived", directoryHint: .isDirectory))])
    #expect(model.errorMessage == nil)
}

private final class RecordingArchivedCodexAppOpener: CodexAppOpening, @unchecked Sendable {
    private(set) var openedTargets: [CodexOpenTarget] = []

    func open(_ target: CodexOpenTarget) throws {
        openedTargets.append(target)
    }
}

private func temporaryDatabaseURL() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "ArchivedTasksModelTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appending(path: "operator.sqlite")
}
