import Foundation

public struct CursorRepositoryRegistrationDraft: Equatable, Sendable {
    public let name: String
    public let localPath: String
    public let githubURL: URL
    public var defaultBranch: String

    public init(name: String, localPath: String, githubURL: URL, defaultBranch: String) {
        self.name = name
        self.localPath = localPath
        self.githubURL = githubURL
        self.defaultBranch = defaultBranch
    }
}

public struct CursorRepositoryRegistrationService: Sendable {
    private let store: CursorOperatorStore
    private let inspector: any CursorRepositoryInspecting

    public init(
        store: CursorOperatorStore,
        inspector: any CursorRepositoryInspecting = CursorGitRepositoryInspector()
    ) {
        self.store = store
        self.inspector = inspector
    }

    public func prepareRepository(at repositoryURL: URL) throws -> CursorRepositoryRegistrationDraft {
        let inspection = try inspector.inspect(repositoryURL)
        return CursorRepositoryRegistrationDraft(
            name: inspection.name,
            localPath: inspection.localPath,
            githubURL: inspection.githubURL,
            defaultBranch: inspection.defaultBranch
        )
    }

    public func saveRepository(
        _ draft: CursorRepositoryRegistrationDraft,
        defaultBranch: String? = nil,
        now: Date = Date()
    ) throws -> CursorRepository {
        try store.createRepository(
            name: draft.name,
            localPath: draft.localPath,
            githubURL: draft.githubURL,
            defaultBranch: defaultBranch ?? draft.defaultBranch,
            now: now
        )
    }
}
