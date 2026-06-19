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

    public init(
        repositoryID: UUID? = nil,
        title: String = "",
        prompt: String = "",
        autoCreatePR: Bool = false
    ) {
        self.repositoryID = repositoryID
        self.title = title
        self.prompt = prompt
        self.autoCreatePR = autoCreatePR
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
            autoCreatePR: autoCreatePR
        )
    }
}

public struct CursorSendPreview: Equatable, Sendable {
    public let repositoryURL: URL
    public let startingRef: String
    public let model: String
    public let autoCreatePR: Bool
    public let prompt: String

    public init(task: CursorTask, repository: CursorRepository) throws {
        guard task.repositoryID == repository.id else {
            throw CursorOperatorStoreError.repositoryNotFound
        }

        repositoryURL = repository.githubURL
        startingRef = repository.defaultBranch
        model = CursorModel.fixed
        autoCreatePR = task.autoCreatePR
        prompt = task.prompt
    }
}
