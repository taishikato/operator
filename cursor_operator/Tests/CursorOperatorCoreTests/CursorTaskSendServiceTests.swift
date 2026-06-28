import Foundation
import Testing
@testable import CursorOperatorCore

@Test func sendServiceRecordsSuccessfulFakeRuntimeAndMovesTaskRunning() async throws {
    let fixture = try SendServiceFixture()
    let runtime = FakeCursorRuntime(result: .success(CursorCloudAgentReference(
        agentID: "agent-123",
        runID: "run-123",
        openURL: URL(string: "https://cursor.com/agents/agent-123")!
    )))
    let service = CursorTaskSendService(
        store: fixture.store,
        credentialReadiness: CursorSendReadiness(provider: fixture.readyProvider),
        runtime: runtime
    )

    let attempt = try await service.send(taskID: fixture.task.id)

    #expect(attempt.status == .succeeded)
    #expect(attempt.cursorAgentID == "agent-123")
    #expect(attempt.cursorRunID == "run-123")
    #expect(attempt.cursorURL == URL(string: "https://cursor.com/agents/agent-123")!)
    #expect(try fixture.store.task(id: fixture.task.id)?.status == .running)
    #expect(runtime.requests == [CursorCloudAgentRequestPreview(
        agentName: fixture.task.title,
        prompt: fixture.task.prompt,
        repositoryURL: fixture.repository.githubURL,
        startingRef: fixture.repository.defaultBranch,
        model: CursorModel.fixed,
        autoCreatePR: fixture.task.autoCreatePR
    )])
}

@Test func sendServiceRecordsCursorHarnessRunThroughNeutralRunsAPI() async throws {
    let fixture = try SendServiceFixture(
        taskHarness: .codex,
        reasoningEffort: .high,
        useFastModel: true
    )
    let runtime = FakeCursorRuntime(result: .success(CursorCloudAgentReference(
        agentID: "agent-operator",
        runID: "run-operator",
        openURL: URL(string: "https://cursor.com/agents/agent-operator")!
    )))
    let service = CursorTaskSendService(
        store: fixture.store,
        credentialReadiness: CursorSendReadiness(provider: fixture.readyProvider),
        runtime: runtime
    )

    _ = try await service.send(taskID: fixture.task.id)

    let run = try #require(fixture.store.runs(taskID: fixture.task.id).last)
    #expect(run.harness == .cursor)
    #expect(run.prompt == "Prompt exactly")
    #expect(run.reasoningEffort == .high)
    #expect(run.useFastModel)
}

@Test func sendServiceRecordsFailureMovesTaskFailedAndAllowsExplicitRetry() async throws {
    let fixture = try SendServiceFixture()
    let runtime = FakeCursorRuntime(result: .failure(CursorRuntimeFailure(
        message: "HTTP 500 body {\"token\":\"crsr_secret_123\",\"detail\":\"raw response\"}"
    )))
    let service = CursorTaskSendService(
        store: fixture.store,
        credentialReadiness: CursorSendReadiness(provider: fixture.readyProvider),
        runtime: runtime
    )

    let failedAttempt = try await service.send(taskID: fixture.task.id)

    #expect(failedAttempt.status == .failed)
    #expect(failedAttempt.errorMessage == "Cursor run failed. See Cursor for details.")
    #expect(failedAttempt.errorMessage?.contains("crsr_secret_123") == false)
    #expect((failedAttempt.errorMessage?.count ?? 0) <= 160)
    #expect(try fixture.store.task(id: fixture.task.id)?.status == .failed)

    _ = try fixture.store.recoverTaskForRetry(id: fixture.task.id)
    runtime.result = .success(CursorCloudAgentReference(
        agentID: "agent-456",
        runID: "run-456",
        openURL: URL(string: "https://cursor.com/agents/agent-456")!
    ))
    let retryAttempt = try await service.send(taskID: fixture.task.id)

    #expect(retryAttempt.status == .succeeded)
    #expect(try fixture.store.runAttempts(taskID: fixture.task.id).map(\.status) == [.failed, .succeeded])
}

@Test func sendServiceBlocksMissingCredentialsAndPreventsSecondSuccessfulSend() async throws {
    let fixture = try SendServiceFixture()
    let missingService = CursorTaskSendService(
        store: fixture.store,
        credentialReadiness: CursorSendReadiness(provider: fixture.missingProvider),
        runtime: FakeCursorRuntime(result: .failure(CursorRuntimeFailure(message: "unused")))
    )

    await #expect(throws: CursorTaskSendError.missingCredentials) {
        try await missingService.send(taskID: fixture.task.id)
    }

    let runtime = FakeCursorRuntime(result: .success(CursorCloudAgentReference(
        agentID: "agent-123",
        runID: "run-123",
        openURL: URL(string: "https://cursor.com/agents/agent-123")!
    )))
    let readyService = CursorTaskSendService(
        store: fixture.store,
        credentialReadiness: CursorSendReadiness(provider: fixture.readyProvider),
        runtime: runtime
    )
    _ = try await readyService.send(taskID: fixture.task.id)

    await #expect(throws: CursorTaskLifecycleError.taskAlreadyHasSuccessfulRun) {
        try await readyService.send(taskID: fixture.task.id)
    }
}

@Test func sendServiceClaimsTaskBeforeStartingRuntimeSoConcurrentSendsDoNotDuplicateRuns() async throws {
    let fixture = try SendServiceFixture()
    let runtime = SlowCursorRuntime()
    let service = CursorTaskSendService(
        store: fixture.store,
        credentialReadiness: CursorSendReadiness(provider: fixture.readyProvider),
        runtime: runtime
    )

    async let firstSend: CursorRunAttempt = service.send(taskID: fixture.task.id)
    try await Task.sleep(nanoseconds: 20_000_000)

    await #expect(throws: CursorTaskLifecycleError.taskAlreadyHasSuccessfulRun) {
        try await service.send(taskID: fixture.task.id)
    }

    let firstAttempt = try await firstSend
    #expect(firstAttempt.status == .succeeded)
    #expect(runtime.startCount == 1)
}

@Test func sendServiceSurfacesStartedRunReferenceWhenRecordingSuccessFails() async throws {
    let fixture = try SendServiceFixture()
    let runtime = ArchivingCursorRuntime(store: fixture.store, taskID: fixture.task.id)
    let service = CursorTaskSendService(
        store: fixture.store,
        credentialReadiness: CursorSendReadiness(provider: fixture.readyProvider),
        runtime: runtime
    )

    await #expect(throws: CursorTaskSendError.startedRunCouldNotBeRecorded(
        CursorCloudAgentReference(
            agentID: "agent-orphan",
            runID: "run-orphan",
            openURL: URL(string: "https://cursor.com/agents/agent-orphan")!
        )
    )) {
        try await service.send(taskID: fixture.task.id)
    }

    let attempt = try #require(fixture.store.runAttempts(taskID: fixture.task.id).last)
    #expect(attempt.status == .failed)
    #expect(attempt.cursorAgentID == "agent-orphan")
    #expect(attempt.cursorRunID == "run-orphan")
    #expect(attempt.cursorURL == URL(string: "https://cursor.com/agents/agent-orphan")!)
}

@Test func sendServiceClearsPendingClaimWhenRuntimeThrowsUnexpectedError() async throws {
    let fixture = try SendServiceFixture()
    let failingService = CursorTaskSendService(
        store: fixture.store,
        credentialReadiness: CursorSendReadiness(provider: fixture.readyProvider),
        runtime: UnexpectedErrorCursorRuntime()
    )

    do {
        _ = try await failingService.send(taskID: fixture.task.id)
        Issue.record("Send should rethrow the unexpected runtime error.")
    } catch UnexpectedRuntimeError.interrupted {
    }

    let failedAttempt = try #require(fixture.store.runAttempts(taskID: fixture.task.id).last)
    #expect(failedAttempt.status == .failed)
    #expect(failedAttempt.errorMessage == "Cursor send was interrupted before Cursor returned a run reference.")

    _ = try fixture.store.recoverTaskForRetry(id: fixture.task.id)
    let retryService = CursorTaskSendService(
        store: fixture.store,
        credentialReadiness: CursorSendReadiness(provider: fixture.readyProvider),
        runtime: FakeCursorRuntime(result: .success(CursorCloudAgentReference(
            agentID: "agent-retry",
            runID: "run-retry",
            openURL: URL(string: "https://cursor.com/agents/agent-retry")!
        )))
    )
    let retryAttempt = try await retryService.send(taskID: fixture.task.id)

    #expect(retryAttempt.status == .succeeded)
    #expect(try fixture.store.runAttempts(taskID: fixture.task.id).map(\.status) == [.failed, .succeeded])
}

@Test func boardProjectionSurfacesLatestFailedSendAttemptOnReadyCard() async throws {
    let fixture = try SendServiceFixture()
    let runtime = FakeCursorRuntime(result: .failure(CursorRuntimeFailure(message: "Cursor rejected the run request.")))
    let service = CursorTaskSendService(
        store: fixture.store,
        credentialReadiness: CursorSendReadiness(provider: fixture.readyProvider),
        runtime: runtime
    )

    _ = try await service.send(taskID: fixture.task.id)

    let projection = try CursorBoardProjection.load(from: fixture.store)
    let failedCard = try #require(projection.columns.first { $0.id == .failed }?.cards.first)
    #expect(failedCard.failedSendMessage == "Cursor rejected the run request.")
}

private final class FakeCursorRuntime: CursorCloudAgentRuntime, @unchecked Sendable {
    var result: Result<CursorCloudAgentReference, CursorRuntimeFailure>
    private(set) var requests: [CursorCloudAgentRequestPreview] = []

    init(result: Result<CursorCloudAgentReference, CursorRuntimeFailure>) {
        self.result = result
    }

    func startCloudAgent(request: CursorCloudAgentRequestPreview, apiKey: String) async throws -> CursorCloudAgentReference {
        requests.append(request)
        return try result.get()
    }
}

private enum UnexpectedRuntimeError: Error, Equatable {
    case interrupted
}

private struct UnexpectedErrorCursorRuntime: CursorCloudAgentRuntime {
    func startCloudAgent(request: CursorCloudAgentRequestPreview, apiKey: String) async throws -> CursorCloudAgentReference {
        throw UnexpectedRuntimeError.interrupted
    }
}

private final class ArchivingCursorRuntime: CursorCloudAgentRuntime, @unchecked Sendable {
    let store: CursorOperatorStore
    let taskID: UUID

    init(store: CursorOperatorStore, taskID: UUID) {
        self.store = store
        self.taskID = taskID
    }

    func startCloudAgent(request: CursorCloudAgentRequestPreview, apiKey: String) async throws -> CursorCloudAgentReference {
        _ = try store.archiveTask(id: taskID)
        return CursorCloudAgentReference(
            agentID: "agent-orphan",
            runID: "run-orphan",
            openURL: URL(string: "https://cursor.com/agents/agent-orphan")!
        )
    }
}

private final class SlowCursorRuntime: CursorCloudAgentRuntime, @unchecked Sendable {
    private let lock = NSLock()
    private var starts = 0

    var startCount: Int {
        lock.withLock { starts }
    }

    func startCloudAgent(request: CursorCloudAgentRequestPreview, apiKey: String) async throws -> CursorCloudAgentReference {
        lock.withLock {
            starts += 1
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        return CursorCloudAgentReference(
            agentID: "agent-slow",
            runID: "run-slow",
            openURL: URL(string: "https://cursor.com/agents/agent-slow")!
        )
    }
}

private struct SendServiceFixture {
    let store: CursorOperatorStore
    let repository: CursorRepository
    let task: CursorTask
    let readyProvider: CursorCredentialProvider
    let missingProvider: CursorCredentialProvider

    init(
        taskHarness: CursorHarness = .cursor,
        reasoningEffort: CursorReasoningEffort = .medium,
        useFastModel: Bool = false
    ) throws {
        store = try CursorOperatorStore(databaseURL: Self.temporaryDatabaseURL())
        repository = try store.createRepository(
            name: "operator",
            localPath: "/tmp/operator",
            githubURL: URL(string: "https://github.com/example/operator")!,
            defaultBranch: "main"
        )
        task = try store.createTask(
            repositoryID: repository.id,
            title: "Send",
            prompt: "Prompt exactly",
            autoCreatePR: true,
            reasoningEffort: reasoningEffort,
            useFastModel: useFastModel,
            harness: taskHarness
        )
        readyProvider = CursorCredentialProvider(
            store: InMemoryCursorCredentialStore(apiKey: "crsr_test_key"),
            environment: [:]
        )
        missingProvider = CursorCredentialProvider(
            store: InMemoryCursorCredentialStore(),
            environment: [:]
        )
    }

    private static func temporaryDatabaseURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "CursorTaskSendServiceTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "operator.sqlite")
    }
}
