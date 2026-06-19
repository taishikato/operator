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

    private static func sanitized(_ message: String) -> String {
        let collapsed = message
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !collapsed.isEmpty else {
            return "Cursor run failed."
        }

        if collapsed.contains("{")
            || collapsed.range(of: "body", options: .caseInsensitive) != nil
            || collapsed.range(of: "authorization", options: .caseInsensitive) != nil
            || collapsed.range(of: "crsr_", options: .caseInsensitive) != nil {
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
}

public extension CursorCloudAgentRuntime {
    func waitForRun(reference: CursorCloudAgentReference, apiKey: String) async throws -> CursorCloudAgentRunCompletion {
        throw CursorRuntimeFailure(message: "Cursor runtime does not support run monitoring.")
    }
}

public enum CursorTaskSendError: Error, Equatable, Sendable {
    case missingCredentials
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
        let apiKey = try credentialReadiness.apiKeyForSending()
        guard let task = try store.task(id: taskID),
              let repository = try store.repository(id: task.repositoryID) else {
            throw CursorOperatorStoreError.taskNotFound
        }

        guard try store.runAttempts(taskID: task.id).allSatisfy({ $0.status != .succeeded }) else {
            throw CursorTaskLifecycleError.taskAlreadyHasSuccessfulRun
        }

        let preview = try CursorSendPreview(task: task, repository: repository)
        let request = CursorCloudAgentRequestPreview(
            prompt: preview.prompt,
            repositoryURL: preview.repositoryURL,
            startingRef: preview.startingRef,
            model: preview.model,
            autoCreatePR: preview.autoCreatePR
        )

        do {
            let reference = try await runtime.startCloudAgent(request: request, apiKey: apiKey)
            return try store.recordSuccessfulSendAttempt(
                taskID: task.id,
                repositoryURL: request.repositoryURL,
                startingRef: request.startingRef,
                model: request.model,
                autoCreatePR: request.autoCreatePR,
                prompt: request.prompt,
                cursorAgentID: reference.agentID,
                cursorRunID: reference.runID,
                cursorURL: reference.openURL
            )
        } catch let failure as CursorRuntimeFailure {
            return try store.recordFailedSendAttempt(
                taskID: task.id,
                repositoryURL: request.repositoryURL,
                startingRef: request.startingRef,
                model: request.model,
                autoCreatePR: request.autoCreatePR,
                prompt: request.prompt,
                errorMessage: failure.message
            )
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
