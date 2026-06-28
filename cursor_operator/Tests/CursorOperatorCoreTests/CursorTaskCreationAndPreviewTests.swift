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
    #expect(task.reasoningEffort == .medium)
    #expect(task.useFastModel == false)
    #expect(task.harness == .cursor)
    #expect(task.status == .ready)
}

@Test func taskCreationDraftDefaultsAutoSendOffAndStoresOptInState() {
    #expect(CursorTaskCreationDraft().autoSend == false)
    #expect(CursorTaskCreationDraft().reasoningEffort == .medium)
    #expect(CursorTaskCreationDraft().useFastModel == false)
    #expect(CursorTaskCreationDraft().harness == .cursor)
    #expect(CursorTaskCreationDraft(autoSend: true).autoSend)
}

@MainActor
@Test func newTaskDraftUsesStoredDefaultHarness() throws {
    let settingsStore = InMemoryOperatorSettingsStore()
    try OperatorSettingsManager(store: settingsStore).setDefaultHarness(.codex)

    let model = CursorBoardModel(
        store: try CursorOperatorStore(databaseURL: temporaryTaskCreationDatabaseURL()),
        settings: OperatorSettingsManager(store: settingsStore)
    )

    #expect(model.creationDraft.harness == .codex)
}

@Test func taskCreationDraftStoresHarnessReasoningAndFastModelIntent() throws {
    let store = try CursorOperatorStore(databaseURL: temporaryTaskCreationDatabaseURL())
    let repository = try store.createRepository(
        name: "operator",
        localPath: "/tmp/operator",
        githubURL: URL(string: "https://github.com/example/operator")!,
        defaultBranch: "main"
    )
    let draft = CursorTaskCreationDraft(
        repositoryID: repository.id,
        title: "Use other harnesses later",
        prompt: "Keep the execution intent durable.",
        autoCreatePR: true,
        reasoningEffort: .high,
        useFastModel: true,
        harness: .codex
    )

    let task = try draft.createTask(in: store)

    #expect(task.autoCreatePR)
    #expect(task.reasoningEffort == .high)
    #expect(task.useFastModel)
    #expect(task.harness == .codex)
}

@Test func codexTaskCreationStoresXHighReasoningEffort() throws {
    let store = try CursorOperatorStore(databaseURL: temporaryTaskCreationDatabaseURL())
    let repository = try store.createRepository(
        name: "operator",
        localPath: "/tmp/operator",
        githubURL: URL(string: "https://github.com/example/operator")!,
        defaultBranch: "main"
    )
    let draft = CursorTaskCreationDraft(
        repositoryID: repository.id,
        title: "Deep Codex pass",
        prompt: "Use the highest supported Codex effort.",
        reasoningEffort: .xhigh,
        harness: .codex
    )

    let task = try draft.createTask(in: store)

    #expect(task.reasoningEffort == .xhigh)
    #expect(task.harness == .codex)
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
        autoCreatePR: true,
        reasoningEffort: .low,
        useFastModel: true,
        harness: .claudeCode
    )

    #expect(edited.title == "Edited")
    #expect(edited.prompt == "Edited prompt\nwith spacing  ")
    #expect(edited.autoCreatePR)
    #expect(edited.reasoningEffort == .low)
    #expect(edited.useFastModel)
    #expect(edited.harness == .claudeCode)
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
        autoCreatePR: true,
        reasoningEffort: .high,
        useFastModel: true,
        harness: .cursor
    )

    let preview = try CursorSendPreview(task: task, repository: repository)

    #expect(preview.agentName == "Preview")
    #expect(preview.repositoryURL == repository.githubURL)
    #expect(preview.startingRef == "trunk")
    #expect(preview.model == CursorModel.fixed)
    #expect(preview.autoCreatePR)
    #expect(preview.reasoningEffort == .high)
    #expect(preview.useFastModel)
    #expect(preview.harness == .cursor)
    #expect(preview.prompt == prompt)
}

@Test func codexSendPreviewUsesCodexModelAndIgnoresCursorOnlyFields() throws {
    let repository = CursorRepository(
        id: UUID(),
        name: "operator",
        localPath: "/tmp/operator",
        githubURL: URL(string: "https://github.com/example/operator")!,
        defaultBranch: "trunk",
        createdAt: Date(),
        updatedAt: Date()
    )
    let task = CursorTask.new(
        repositoryID: repository.id,
        title: "Codex Preview",
        prompt: "Codex should not receive Cursor-only settings.",
        autoCreatePR: true,
        reasoningEffort: .xhigh,
        useFastModel: true,
        harness: .codex
    )

    let preview = try CursorSendPreview(task: task, repository: repository)

    #expect(preview.model == CodexModel.fixed)
    #expect(preview.autoCreatePR == false)
    #expect(preview.useFastModel == false)
    #expect(preview.reasoningEffort == .xhigh)
    #expect(preview.harness == .codex)
}

private func temporaryTaskCreationDatabaseURL() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "CursorTaskCreationTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appending(path: "operator.sqlite")
}

private final class InMemoryOperatorSettingsStore: OperatorSettingsStoring, @unchecked Sendable {
    private var storedDefaultHarness: String?

    func defaultHarnessRawValue() -> String? {
        storedDefaultHarness
    }

    func setDefaultHarnessRawValue(_ rawValue: String?) {
        storedDefaultHarness = rawValue
    }
}
