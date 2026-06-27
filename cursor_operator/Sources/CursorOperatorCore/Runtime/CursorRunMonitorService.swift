import Foundation

public enum CursorRunMonitorOutcome: Equatable, Sendable {
    case completed(taskID: UUID, runID: String)
    case failed(taskID: UUID, runID: String, message: String)
    case monitoringFailed(taskID: UUID, runID: String, message: String)
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
        let completion: CursorCloudAgentRunCompletion
        do {
            completion = try await runtime.waitForRun(
                reference: runningReference.reference,
                apiKey: apiKey
            )
        } catch {
            return .monitoringFailed(
                taskID: runningReference.taskID,
                runID: runningReference.reference.runID,
                message: Self.userFacingMessage(for: error)
            )
        }

        if completion.isComplete {
            if try store.task(id: runningReference.taskID)?.status == .running {
                _ = try store.markTaskDone(id: runningReference.taskID)
            }
            return .completed(taskID: runningReference.taskID, runID: runningReference.reference.runID)
        }

        if completion.isTerminalFailure {
            let message = completion.terminalFailureMessage
            if try store.task(id: runningReference.taskID)?.status == .running {
                _ = try store.recordRunFailure(
                    taskID: runningReference.taskID,
                    runID: runningReference.reference.runID,
                    errorMessage: message
                )
            }
            return .failed(
                taskID: runningReference.taskID,
                runID: runningReference.reference.runID,
                message: message
            )
        }

        return .stillRunning(taskID: runningReference.taskID, runID: runningReference.reference.runID)
    }

    private static func userFacingMessage(for error: Error) -> String {
        if let runtimeFailure = error as? CursorRuntimeFailure {
            return runtimeFailure.message
        }
        if let localizedError = error as? LocalizedError,
           let errorDescription = localizedError.errorDescription {
            return errorDescription
        }
        return "Operator could not confirm the run status."
    }
}

private struct RunningRunReference: Sendable {
    let taskID: UUID
    let reference: CursorCloudAgentReference
}

private extension CursorRunMonitorOutcome {
    var sortKey: String {
        switch self {
        case let .completed(taskID, runID),
             let .failed(taskID, runID, _),
             let .monitoringFailed(taskID, runID, _),
             let .stillRunning(taskID, runID):
            "\(taskID.uuidString)-\(runID)"
        }
    }
}
