import Foundation
import Testing
@testable import CursorOperatorCore

@Test func runMonitorWaitsForSavedRunReferenceAndMovesCompletedTaskDone() async throws {
    let fixture = try RunMonitorFixture()
    let runtime = FakeRunMonitoringRuntime(completion: CursorCloudAgentRunCompletion(
        status: "finished",
        result: "Run completed"
    ))
    let service = CursorRunMonitorService(
        store: fixture.store,
        credentialReadiness: CursorSendReadiness(provider: fixture.readyProvider),
        runtime: runtime
    )

    let outcomes = try await service.resumeRunningTasks()

    #expect(outcomes == [.completed(taskID: fixture.task.id, runID: "run-monitor")])
    #expect(try fixture.store.task(id: fixture.task.id)?.status == .done)
    #expect(runtime.waits == [CursorCloudAgentReference(
        agentID: "agent-monitor",
        runID: "run-monitor",
        openURL: URL(string: "https://cursor.com/agents/agent-monitor")!
    )])
}

@Test func runMonitorLeavesRunningTaskWhenRuntimeCannotConfirmCompletion() async throws {
    let fixture = try RunMonitorFixture()
    let runtime = FakeRunMonitoringRuntime(completion: CursorCloudAgentRunCompletion(
        status: "running",
        result: nil
    ))
    let service = CursorRunMonitorService(
        store: fixture.store,
        credentialReadiness: CursorSendReadiness(provider: fixture.readyProvider),
        runtime: runtime
    )

    let outcomes = try await service.resumeRunningTasks()

    #expect(outcomes == [.stillRunning(taskID: fixture.task.id, runID: "run-monitor")])
    #expect(try fixture.store.task(id: fixture.task.id)?.status == .running)
}

@Test func runMonitorMovesTerminalFailedRunToFailedTaskAndPersistsMessage() async throws {
    let fixture = try RunMonitorFixture()
    let runtime = FakeRunMonitoringRuntime(completion: CursorCloudAgentRunCompletion(
        status: "failed",
        result: "Cursor run failed during execution."
    ))
    let service = CursorRunMonitorService(
        store: fixture.store,
        credentialReadiness: CursorSendReadiness(provider: fixture.readyProvider),
        runtime: runtime
    )

    let outcomes = try await service.resumeRunningTasks()

    #expect(outcomes == [.failed(
        taskID: fixture.task.id,
        runID: "run-monitor",
        message: "Cursor run failed during execution."
    )])
    #expect(try fixture.store.task(id: fixture.task.id)?.status == .failed)

    let projection = try CursorBoardProjection.load(from: fixture.store)
    let failedCard = try #require(projection.columns.first { $0.id == .failed }?.cards.first)
    #expect(failedCard.runStatusText == "Run failed")
    #expect(failedCard.failedSendMessage == "Cursor run failed during execution.")
}

@Test func runningTaskCardShowsIncompleteRunStatusAndDoneCardShowsCompletedRunStatus() throws {
    let runningTask = CursorTask.new(repositoryID: UUID(), title: "Running", prompt: "Prompt")
    let doneTask = CursorTask.new(repositoryID: UUID(), title: "Done", prompt: "Prompt")
    let running = try CursorTaskLifecyclePolicy.recordSuccessfulSend(for: runningTask)
    let done = try CursorTaskLifecyclePolicy.markDone(CursorTaskLifecyclePolicy.recordSuccessfulSend(for: doneTask))
    let projection = CursorBoardProjection(tasks: [running, done])

    let runningCard = projection.columns.first { $0.id == .running }?.cards.first
    let doneCard = projection.columns.first { $0.id == .done }?.cards.first

    #expect(runningCard?.runStatusText == "Run in progress")
    #expect(doneCard?.runStatusText == "Run complete")
}

private final class FakeRunMonitoringRuntime: CursorCloudAgentRuntime, @unchecked Sendable {
    let completion: CursorCloudAgentRunCompletion
    private(set) var waits: [CursorCloudAgentReference] = []

    init(completion: CursorCloudAgentRunCompletion) {
        self.completion = completion
    }

    func startCloudAgent(request: CursorCloudAgentRequestPreview, apiKey: String) async throws -> CursorCloudAgentReference {
        CursorCloudAgentReference(
            agentID: "unused",
            runID: "unused",
            openURL: URL(string: "https://cursor.com/agents/unused")!
        )
    }

    func waitForRun(reference: CursorCloudAgentReference, apiKey: String) async throws -> CursorCloudAgentRunCompletion {
        waits.append(reference)
        return completion
    }
}

private struct RunMonitorFixture {
    let store: CursorOperatorStore
    let task: CursorTask
    let readyProvider: CursorCredentialProvider

    init() throws {
        store = try CursorOperatorStore(databaseURL: Self.temporaryDatabaseURL())
        let repository = try store.createRepository(
            name: "operator",
            localPath: "/tmp/operator-run-monitor",
            githubURL: URL(string: "https://github.com/example/operator")!,
            defaultBranch: "main"
        )
        task = try store.createTask(
            repositoryID: repository.id,
            title: "Monitor",
            prompt: "Prompt"
        )
        _ = try store.recordSuccessfulSendAttempt(
            taskID: task.id,
            repositoryURL: repository.githubURL,
            startingRef: repository.defaultBranch,
            model: CursorModel.fixed,
            autoCreatePR: false,
            prompt: task.prompt,
            cursorAgentID: "agent-monitor",
            cursorRunID: "run-monitor",
            cursorURL: URL(string: "https://cursor.com/agents/agent-monitor")!
        )
        readyProvider = CursorCredentialProvider(
            store: InMemoryCursorCredentialStore(apiKey: "crsr_test_key"),
            environment: [:]
        )
    }

    private static func temporaryDatabaseURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "CursorRunMonitorServiceTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "cursor-operator.sqlite")
    }
}
