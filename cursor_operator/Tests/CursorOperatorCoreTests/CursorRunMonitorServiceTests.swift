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
    #expect(failedCard.latestRun?.status == .failed)
}

@Test func runMonitorFailedRunCanBeRecoveredAndRetried() async throws {
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

    _ = try await service.resumeRunningTasks()
    _ = try fixture.store.recoverTaskForRetry(id: fixture.task.id)
    let retryRun = try fixture.store.recordSuccessfulSendAttempt(
        taskID: fixture.task.id,
        repositoryURL: fixture.repository.githubURL,
        startingRef: fixture.repository.defaultBranch,
        model: CursorModel.fixed,
        autoCreatePR: false,
        prompt: fixture.task.prompt,
        cursorAgentID: "agent-retry",
        cursorRunID: "run-retry",
        cursorURL: URL(string: "https://cursor.com/agents/agent-retry")!
    )

    let runs = try fixture.store.runAttempts(taskID: fixture.task.id)
    #expect(retryRun.cursorRunID == "run-retry")
    #expect(runs.map(\.status) == [.failed, .succeeded])
}

@Test func runMonitorContinuesAfterOneRuntimeWaitFails() async throws {
    let store = try CursorOperatorStore(databaseURL: RunMonitorFixture.temporaryDatabaseURL())
    let repository = try store.createRepository(
        name: "operator",
        localPath: "/tmp/operator-run-monitor-many",
        githubURL: URL(string: "https://github.com/example/operator")!,
        defaultBranch: "main"
    )
    let failingTaskID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let completingTaskID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    let failingTask = try store.createTask(
        id: failingTaskID,
        repositoryID: repository.id,
        title: "Transient failure",
        prompt: "Prompt"
    )
    let completingTask = try store.createTask(
        id: completingTaskID,
        repositoryID: repository.id,
        title: "Complete",
        prompt: "Prompt"
    )
    _ = try store.recordSuccessfulSendAttempt(
        taskID: failingTask.id,
        repositoryURL: repository.githubURL,
        startingRef: repository.defaultBranch,
        model: CursorModel.fixed,
        autoCreatePR: false,
        prompt: failingTask.prompt,
        cursorAgentID: "agent-failing",
        cursorRunID: "run-failing",
        cursorURL: URL(string: "https://cursor.com/agents/agent-failing")!
    )
    _ = try store.recordSuccessfulSendAttempt(
        taskID: completingTask.id,
        repositoryURL: repository.githubURL,
        startingRef: repository.defaultBranch,
        model: CursorModel.fixed,
        autoCreatePR: false,
        prompt: completingTask.prompt,
        cursorAgentID: "agent-completing",
        cursorRunID: "run-completing",
        cursorURL: URL(string: "https://cursor.com/agents/agent-completing")!
    )
    let runtime = SelectiveRunMonitoringRuntime(results: [
        "run-failing": .failure(CursorRuntimeFailure(message: "temporary network failure")),
        "run-completing": .success(CursorCloudAgentRunCompletion(status: "finished", result: "Done"))
    ])
    let service = CursorRunMonitorService(
        store: store,
        credentialReadiness: CursorSendReadiness(provider: RunMonitorFixture.readyProvider()),
        runtime: runtime
    )

    let outcomes = try await service.resumeRunningTasks()

    #expect(outcomes == [
        .monitoringFailed(
            taskID: failingTaskID,
            runID: "run-failing",
            message: "temporary network failure"
        ),
        .completed(taskID: completingTaskID, runID: "run-completing")
    ])
    #expect(try store.task(id: failingTaskID)?.status == .running)
    #expect(try store.task(id: completingTaskID)?.status == .done)
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

private final class SelectiveRunMonitoringRuntime: CursorCloudAgentRuntime, @unchecked Sendable {
    let results: [String: Result<CursorCloudAgentRunCompletion, Error>]

    init(results: [String: Result<CursorCloudAgentRunCompletion, Error>]) {
        self.results = results
    }

    func startCloudAgent(request: CursorCloudAgentRequestPreview, apiKey: String) async throws -> CursorCloudAgentReference {
        CursorCloudAgentReference(
            agentID: "unused",
            runID: "unused",
            openURL: URL(string: "https://cursor.com/agents/unused")!
        )
    }

    func waitForRun(reference: CursorCloudAgentReference, apiKey: String) async throws -> CursorCloudAgentRunCompletion {
        switch results[reference.runID] {
        case let .success(completion):
            return completion
        case let .failure(error):
            throw error
        case nil:
            throw CursorRuntimeFailure(message: "Unexpected run.")
        }
    }
}

private struct RunMonitorFixture {
    let store: CursorOperatorStore
    let repository: CursorRepository
    let task: CursorTask
    let readyProvider: CursorCredentialProvider

    init() throws {
        store = try CursorOperatorStore(databaseURL: Self.temporaryDatabaseURL())
        repository = try store.createRepository(
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

    static func readyProvider() -> CursorCredentialProvider {
        CursorCredentialProvider(
            store: InMemoryCursorCredentialStore(apiKey: "crsr_test_key"),
            environment: [:]
        )
    }

    static func temporaryDatabaseURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "CursorRunMonitorServiceTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "operator.sqlite")
    }
}
