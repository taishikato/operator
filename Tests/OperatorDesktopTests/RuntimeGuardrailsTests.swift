import Foundation
import GRDB
import Testing
@testable import OperatorDesktop

@Test func runtimeGuardrailsDeclareForbiddenMVPResponsibilities() {
    let guardrails = OperatorRuntimeGuardrails.mvp

    #expect(guardrails.forbiddenResponsibilities == [
        .scheduling,
        .triggerQueue,
        .concurrencyControl,
        .backlogColumn,
        .runningColumn,
        .reviewToReadyMovement,
        .rerunAfterSuccessfulSend,
        .hardDelete,
        .automaticWorktreeCleanup,
        .pullRequestCreation,
        .branchCreation,
        .diffInspection,
        .changedFileCount,
        .testResultTracking,
        .commitStatusTracking,
        .codexCompletionTracking,
        .appServerRawEventPersistence,
        .codexTranscriptPersistence
    ])
    #expect(guardrails.maximumFailureErrorMessageLength == 160)
}

@Test func runtimeGuardrailsAlignWithShellNavigationAndBoardColumns() {
    let guardrails = OperatorRuntimeGuardrails.mvp
    let shell = OperatorShellSpec.mvp

    #expect(shell.launchDestination == .board)
    #expect(shell.board.columns.map(\.id) == guardrails.allowedBoardColumns)
    #expect(shell.navigationDestinations == guardrails.allowedNavigationDestinations)
    #expect(Set(shell.board.columns.map(\.title)).isDisjoint(with: guardrails.forbiddenVisibleLabels))
}

@Test func runPersistenceSchemaStoresOnlyTriggerLevelMetadata() throws {
    let databaseURL = try temporaryDatabaseURL()
    _ = try OperatorStore(databaseURL: databaseURL)
    let dbQueue = try DatabaseQueue(path: databaseURL.path)

    let runColumns: [String] = try dbQueue.read { db in
        try Row.fetchAll(db, sql: "PRAGMA table_info(runs)").map { row in
            let name: String = row["name"]
            return name
        }
    }

    #expect(runColumns == OperatorRuntimeGuardrails.mvp.allowedRunPersistenceColumns)
    #expect(Set(runColumns).isDisjoint(with: OperatorRuntimeGuardrails.mvp.forbiddenRunPersistenceColumns))
}

@Test func successfulTaskProjectionsExposeOpenButNoSendOrRerunAffordance() throws {
    let store = try OperatorStore(databaseURL: temporaryDatabaseURL())
    let repository = try store.createRepository(name: "operator", path: "/tmp/operator", defaultBranch: "main")
    let task = try store.createTask(repositoryID: repository.id, title: "Already sent", prompt: "Prompt")
    let threadURL = URL(string: "codex://thread/thread-guardrail")!
    _ = try store.recordSuccessfulRun(
        taskID: task.id,
        worktreePath: "/tmp/worktrees/sent",
        baseBranch: "main",
        baseRef: "abc123",
        codexThreadID: "thread-guardrail",
        codexThreadURL: threadURL
    )

    let projection = try TaskBoardProjection.load(from: store)
    let card = try #require(projection.column(.review).cards.first)
    let inspector = try #require(projection.inspector(taskID: task.id))

    #expect(card.canSendToCodex == false)
    #expect(card.codexSendLabel != "Rerun")
    #expect(card.canOpenInCodexApp)
    #expect(inspector.canSendToCodex == false)
    #expect(inspector.codexSendLabel != "Rerun")
    #expect(inspector.canOpenInCodexApp)
}

@Test func sendFlowStoresThreadReferenceButNoRawEventsOrTranscriptContent() async throws {
    let store = try OperatorStore(databaseURL: temporaryDatabaseURL())
    let repository = try store.createRepository(name: "operator", path: "/tmp/operator", defaultBranch: "main")
    let task = try store.createTask(
        repositoryID: repository.id,
        title: "Guard storage",
        prompt: "Prompt may mention RAW_EVENT_MARKER and TRANSCRIPT_MARKER but run storage must not copy it."
    )
    let worktreeURL = URL(filePath: "/tmp/operator-worktree-guardrail")
    let worktreePreparer = GuardrailWorktreePreparer(worktreeURL: worktreeURL)
    let appServer = GuardrailAppServerClient(
        thread: CodexThreadReference(id: "thread-guardrail", url: URL(string: "codex://thread/guardrail"))
    )
    let service = CodexTriggerService(
        store: store,
        worktreePreparer: worktreePreparer,
        appServerClient: appServer
    )

    let run = try await service.sendTaskToCodex(taskID: task.id)
    let storedRuns = try store.runs(taskID: task.id)

    #expect(storedRuns.map(\.id) == [run.id])
    #expect(storedRuns.map(\.status) == [.triggered])
    #expect(run.codexThreadID == "thread-guardrail")
    #expect(run.codexThreadURL == URL(string: "codex://thread/guardrail"))
    #expect(run.errorMessage == nil)
    #expect(run.serializedTriggerFields.contains("RAW_EVENT_MARKER") == false)
    #expect(run.serializedTriggerFields.contains("TRANSCRIPT_MARKER") == false)
}

private final class GuardrailWorktreePreparer: CodexWorktreePreparing, @unchecked Sendable {
    private let worktreeURL: URL

    init(worktreeURL: URL) {
        self.worktreeURL = worktreeURL
    }

    func prepareWorktree(for repository: OperatorRepository) throws -> PreparedWorktree {
        PreparedWorktree(worktreeURL: worktreeURL, baseBranch: repository.defaultBranch, baseRef: "abc123")
    }
}

private final class GuardrailAppServerClient: CodexAppServerClient, @unchecked Sendable {
    private let thread: CodexThreadReference

    init(thread: CodexThreadReference) {
        self.thread = thread
    }

    func startThreadAndTurn(_ request: CodexThreadStartRequest) async throws -> CodexThreadReference {
        thread
    }
}

private extension OperatorRun {
    var serializedTriggerFields: String {
        [
            id.uuidString,
            taskID.uuidString,
            repositoryID.uuidString,
            status.rawValue,
            worktreePath,
            baseBranch,
            baseRef,
            codexThreadID,
            codexThreadURL?.absoluteString,
            errorMessage
        ]
            .compactMap(\.self)
            .joined(separator: "\n")
    }
}

private func temporaryDatabaseURL() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "RuntimeGuardrailsTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appending(path: "operator.sqlite")
}
