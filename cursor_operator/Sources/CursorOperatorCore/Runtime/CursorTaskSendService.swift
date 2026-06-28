import Foundation

public protocol CursorCloudAgentRuntime: Sendable {
    func startCloudAgent(request: CursorCloudAgentRequestPreview, apiKey: String) async throws -> CursorCloudAgentReference
    func waitForRun(reference: CursorCloudAgentReference, apiKey: String) async throws -> CursorCloudAgentRunCompletion
}

public struct CursorRuntimeFailure: Error, Equatable, Sendable {
    public let message: String

    public init(message: String) {
        self.message = Self.sanitized(message)
    }

    // Substrings that signal a message may carry a raw response body, a header,
    // or a credential. Matching is intentionally broad: the sanitized output is
    // persisted on the run and rendered in the UI, so we would rather over-redact
    // a benign message than echo an upstream secret. The original detail stays
    // available in Cursor itself.
    private static let sensitiveMarkers = [
        "{",
        "body",
        "authorization",
        "bearer",
        "cookie",
        "token",
        "secret",
        "password",
        "api_key",
        "apikey",
        "crsr_",
    ]

    private static func sanitized(_ message: String) -> String {
        let collapsed = message
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !collapsed.isEmpty else {
            return "Cursor run failed."
        }

        let containsSensitiveMarker = sensitiveMarkers.contains { marker in
            collapsed.range(of: marker, options: .caseInsensitive) != nil
        }
        if containsSensitiveMarker {
            return "Cursor run failed. See Cursor for details."
        }

        if collapsed.count > 160 {
            return "\(collapsed.prefix(157))..."
        }

        return collapsed
    }
}

public struct CursorCloudAgentRunCompletion: Equatable, Sendable {
    public let status: String
    public let result: String?

    public init(status: String, result: String?) {
        self.status = status
        self.result = result
    }

    public var isComplete: Bool {
        let normalized = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["completed", "complete", "finished", "done", "succeeded", "success"].contains(normalized)
    }

    public var isTerminalFailure: Bool {
        let normalized = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["failed", "failure", "cancelled", "canceled", "error", "expired"].contains(normalized)
    }

    public var terminalFailureMessage: String {
        let trimmedResult = result?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedResult, !trimmedResult.isEmpty {
            return trimmedResult
        }
        return "Cursor run ended with status: \(status)."
    }
}

public extension CursorCloudAgentRuntime {
    func waitForRun(reference: CursorCloudAgentReference, apiKey: String) async throws -> CursorCloudAgentRunCompletion {
        throw CursorRuntimeFailure(message: "Cursor runtime does not support run monitoring.")
    }
}

public enum CursorTaskSendError: Error, Equatable, LocalizedError, Sendable {
    case missingCredentials
    case unsupportedHarness(CursorHarness)
    case sendFailed(message: String)
    case startedRunCouldNotBeRecorded(CursorCloudAgentReference)

    public var errorDescription: String? {
        switch self {
        case .missingCredentials:
            "Cursor API key is required before sending."
        case let .unsupportedHarness(harness):
            "\(harness.displayName) sending is not available yet."
        case let .sendFailed(message):
            "Cursor send failed: \(message)"
        case let .startedRunCouldNotBeRecorded(reference):
            "Cursor run started but could not be saved. Agent: \(reference.agentID). Run: \(reference.runID). Open: \(reference.openURL.absoluteString)"
        }
    }
}

public struct CursorTaskSendService: Sendable {
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

    public func send(taskID: UUID) async throws -> CursorRunAttempt {
        guard let task = try store.task(id: taskID),
              let repository = try store.repository(id: task.repositoryID) else {
            throw CursorOperatorStoreError.taskNotFound
        }
        guard task.harness == .cursor else {
            throw CursorTaskSendError.unsupportedHarness(task.harness)
        }

        let apiKey = try credentialReadiness.apiKeyForSending()

        guard try store.runAttempts(taskID: task.id).allSatisfy({ $0.status != .succeeded }) else {
            throw CursorTaskLifecycleError.taskAlreadyHasSuccessfulRun
        }

        let preview = try CursorSendPreview(task: task, repository: repository)
        let request = CursorCloudAgentRequestPreview(
            agentName: preview.agentName,
            prompt: preview.prompt,
            repositoryURL: preview.repositoryURL,
            startingRef: preview.startingRef,
            model: preview.model,
            autoCreatePR: preview.autoCreatePR
        )

        let pendingAttempt = try store.claimSendAttempt(
            taskID: task.id,
            repositoryURL: request.repositoryURL,
            startingRef: request.startingRef,
            model: request.model,
            autoCreatePR: request.autoCreatePR,
            prompt: request.prompt,
            harness: .cursor
        )

        do {
            let reference = try await runtime.startCloudAgent(request: request, apiKey: apiKey)
            do {
                return try store.recordSuccessfulClaimedSendAttempt(
                    id: pendingAttempt.id,
                    cursorAgentID: reference.agentID,
                    cursorRunID: reference.runID,
                    cursorURL: reference.openURL
                )
            } catch {
                _ = try? store.recordFailedClaimedSendAttempt(
                    id: pendingAttempt.id,
                    cursorAgentID: reference.agentID,
                    cursorRunID: reference.runID,
                    cursorURL: reference.openURL,
                    errorMessage: CursorTaskSendError.startedRunCouldNotBeRecorded(reference).errorDescription
                        ?? "Cursor run started but could not be saved."
                )
                throw CursorTaskSendError.startedRunCouldNotBeRecorded(reference)
            }
        } catch let failure as CursorRuntimeFailure {
            return try store.recordFailedClaimedSendAttempt(
                id: pendingAttempt.id,
                errorMessage: failure.message
            )
        } catch {
            _ = try? store.recordFailedClaimedSendAttempt(
                id: pendingAttempt.id,
                errorMessage: "Cursor send was interrupted before Cursor returned a run reference."
            )
            throw error
        }
    }
}

public struct FakeCursorCloudAgentRuntime: CursorCloudAgentRuntime {
    public init() {}

    public func startCloudAgent(request: CursorCloudAgentRequestPreview, apiKey: String) async throws -> CursorCloudAgentReference {
        let agentID = "fake-\(UUID().uuidString)"
        return CursorCloudAgentReference(
            agentID: agentID,
            runID: "run-\(UUID().uuidString)",
            openURL: URL(string: "https://cursor.com/agents/\(agentID)")!
        )
    }

    public func waitForRun(reference: CursorCloudAgentReference, apiKey: String) async throws -> CursorCloudAgentRunCompletion {
        CursorCloudAgentRunCompletion(status: "finished", result: nil)
    }
}
