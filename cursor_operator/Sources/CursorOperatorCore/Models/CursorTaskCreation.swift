import Foundation

public enum CursorTaskCreationError: Error, Equatable, Sendable {
    case repositoryRequired
    case titleRequired
    case promptRequired
}

public struct CursorTaskCreationDraft: Equatable, Sendable {
    public var repositoryID: UUID?
    public var title: String
    public var prompt: String
    public var autoCreatePR: Bool
    public var reasoningEffort: CursorReasoningEffort
    public var useFastModel: Bool
    public var harness: CursorHarness
    public var autoSend: Bool

    public init(
        repositoryID: UUID? = nil,
        title: String = "",
        prompt: String = "",
        autoCreatePR: Bool = false,
        reasoningEffort: CursorReasoningEffort = .medium,
        useFastModel: Bool = false,
        harness: CursorHarness = .cursor,
        autoSend: Bool = false
    ) {
        self.repositoryID = repositoryID
        self.title = title
        self.prompt = prompt
        self.autoCreatePR = autoCreatePR
        self.reasoningEffort = reasoningEffort
        self.useFastModel = useFastModel
        self.harness = harness
        self.autoSend = autoSend
    }

    public func createTask(in store: CursorOperatorStore) throws -> CursorTask {
        guard let repositoryID else {
            throw CursorTaskCreationError.repositoryRequired
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            throw CursorTaskCreationError.titleRequired
        }

        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CursorTaskCreationError.promptRequired
        }

        return try store.createTask(
            repositoryID: repositoryID,
            title: trimmedTitle,
            prompt: prompt,
            autoCreatePR: autoCreatePR,
            reasoningEffort: reasoningEffort,
            useFastModel: useFastModel,
            harness: harness
        )
    }
}

public struct CursorSendPreview: Equatable, Sendable {
    public let agentName: String
    public let repositoryURL: URL
    public let startingRef: String
    public let model: String
    public let autoCreatePR: Bool
    public let reasoningEffort: CursorReasoningEffort
    public let useFastModel: Bool
    public let harness: CursorHarness
    public let prompt: String

    public init(task: CursorTask, repository: CursorRepository) throws {
        guard task.repositoryID == repository.id else {
            throw CursorOperatorStoreError.repositoryNotFound
        }

        let trimmedTitle = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        agentName = trimmedTitle.isEmpty ? "Operator Task" : trimmedTitle
        repositoryURL = repository.githubURL
        startingRef = repository.defaultBranch
        model = CursorModel.fixed
        autoCreatePR = task.autoCreatePR
        reasoningEffort = task.reasoningEffort
        useFastModel = task.useFastModel
        harness = task.harness
        prompt = task.prompt
    }
}
