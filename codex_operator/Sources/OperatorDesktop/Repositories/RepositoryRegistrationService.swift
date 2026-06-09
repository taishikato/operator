import Foundation

public struct RepositoryRegistrationService: Sendable {
    private let store: OperatorStore
    private let inspector: any RepositoryInspecting

    public init(
        store: OperatorStore,
        inspector: any RepositoryInspecting = GitRepositoryInspector()
    ) {
        self.store = store
        self.inspector = inspector
    }

    public func registerRepository(at repositoryURL: URL, now: Date = Date()) throws -> OperatorRepository {
        let inspection = try inspector.inspect(repositoryURL)
        return try store.createRepository(
            name: inspection.name,
            path: inspection.path,
            defaultBranch: inspection.defaultBranch ?? "",
            now: now
        )
    }
}
