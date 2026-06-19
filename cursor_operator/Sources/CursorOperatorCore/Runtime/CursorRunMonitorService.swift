import Foundation

public enum CursorRunMonitorOutcome: Equatable, Sendable {
    case completed(taskID: UUID, runID: String)
    case stillRunning(taskID: UUID, runID: String)
}

public struct CursorRunMonitorService: Sendable {
    private let store: CursorOperatorStore
    private let credentialReadiness: CursorSendReadiness
    private let runtime: any CursorCloudAgentRuntime

    public init(
        store: CursorOperatorStore,
        credentialReadiness: CursorSendReadiness,
        runtime: any CursorCloudAgentRuntime
    ) {
        self.store = store
        self.credentialReadiness = credentialReadiness
        self.runtime = runtime
    }

    public func resumeRunningTasks() async throws -> [CursorRunMonitorOutcome] {
        let apiKey = try credentialReadiness.apiKeyForSending()
        let references = try runningRunReferences()

        return try await withThrowingTaskGroup(of: CursorRunMonitorOutcome.self) { group in
            for reference in references {
                group.addTask {
                    try await waitForRunningTask(reference, apiKey: apiKey)
                }
            }

            var outcomes: [CursorRunMonitorOutcome] = []
            for try await outcome in group {
                outcomes.append(outcome)
            }
            return outcomes.sorted { $0.sortKey < $1.sortKey }
        }
    }

    private func runningRunReferences() throws -> [RunningRunReference] {
        try store.tasks()
            .filter { $0.status == .running }
            .compactMap { task in
                guard let attempt = try store.runAttempts(taskID: task.id).last(where: { $0.status == .succeeded }),
                      let agentID = attempt.cursorAgentID,
                      let runID = attempt.cursorRunID else {
                    return nil
                }
                return RunningRunReference(
                    taskID: task.id,
                    reference: CursorCloudAgentReference(
                        agentID: agentID,
                        runID: runID,
                        openURL: attempt.cursorURL ?? URL(string: "https://cursor.com/agents/\(agentID)")!
                    )
                )
            }
    }

    private func waitForRunningTask(
        _ runningReference: RunningRunReference,
        apiKey: String
    ) async throws -> CursorRunMonitorOutcome {
        let completion = try await runtime.waitForRun(
            reference: runningReference.reference,
            apiKey: apiKey
        )

        if completion.isComplete {
            if try store.task(id: runningReference.taskID)?.status == .running {
                _ = try store.markTaskDone(id: runningReference.taskID)
            }
            return .completed(taskID: runningReference.taskID, runID: runningReference.reference.runID)
        }

        return .stillRunning(taskID: runningReference.taskID, runID: runningReference.reference.runID)
    }
}

private struct RunningRunReference: Sendable {
    let taskID: UUID
    let reference: CursorCloudAgentReference
}

private extension CursorRunMonitorOutcome {
    var sortKey: String {
        switch self {
        case let .completed(taskID, runID), let .stillRunning(taskID, runID):
            "\(taskID.uuidString)-\(runID)"
        }
    }
}
