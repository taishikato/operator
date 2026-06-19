import Foundation
import Testing
@testable import CursorOperatorCore

@Test func taskCreationDraftDefaultsAutoCreatePROffAndStoresPromptAsWritten() throws {
    let store = try CursorOperatorStore(databaseURL: temporaryTaskCreationDatabaseURL())
    let repository = try store.createRepository(
        name: "operator",
        localPath: "/tmp/operator",
        githubURL: URL(string: "https://github.com/example/operator")!,
        defaultBranch: "main"
    )
    let prompt = "Line one\n\nDo exactly this.  "
    let draft = CursorTaskCreationDraft(
        repositoryID: repository.id,
        title: "Implement preview",
        prompt: prompt
    )

    let task = try draft.createTask(in: store)

    #expect(task.title == "Implement preview")
    #expect(task.prompt == prompt)
    #expect(task.autoCreatePR == false)
    #expect(task.status == .ready)
}

@Test func readyTaskCanBeEditedBeforeSending() throws {
    let store = try CursorOperatorStore(databaseURL: temporaryTaskCreationDatabaseURL())
    let repository = try store.createRepository(
        name: "operator",
        localPath: "/tmp/operator",
        githubURL: URL(string: "https://github.com/example/operator")!,
        defaultBranch: "main"
    )
    let task = try store.createTask(repositoryID: repository.id, title: "Original", prompt: "Original prompt")

    let edited = try store.updateTaskContent(
        id: task.id,
        title: "Edited",
        prompt: "Edited prompt\nwith spacing  ",
        autoCreatePR: true
    )

    #expect(edited.title == "Edited")
    #expect(edited.prompt == "Edited prompt\nwith spacing  ")
    #expect(edited.autoCreatePR)
}

@Test func sendPreviewShowsExactCursorRunContextWithoutPromptAugmentation() throws {
    let repository = CursorRepository(
        id: UUID(),
        name: "operator",
        localPath: "/tmp/operator",
        githubURL: URL(string: "https://github.com/example/operator")!,
        defaultBranch: "trunk",
        createdAt: Date(),
        updatedAt: Date()
    )
    let prompt = "Keep this prompt exactly.\nNo hidden additions."
    let task = CursorTask.new(
        repositoryID: repository.id,
        title: "Preview",
        prompt: prompt,
        autoCreatePR: true
    )

    let preview = try CursorSendPreview(task: task, repository: repository)

    #expect(preview.repositoryURL == repository.githubURL)
    #expect(preview.startingRef == "trunk")
    #expect(preview.model == CursorModel.fixed)
    #expect(preview.autoCreatePR)
    #expect(preview.prompt == prompt)
}

private func temporaryTaskCreationDatabaseURL() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "CursorTaskCreationTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appending(path: "cursor-operator.sqlite")
}
