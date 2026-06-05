import Foundation

@MainActor
public final class RepositorySettingsModel: ObservableObject {
    @Published public private(set) var repositories: [OperatorRepository] = []
    @Published public private(set) var errorMessage: String?

    private let store: OperatorStore
    private let registrationService: RepositoryRegistrationService
    private var defaultBranchDrafts: [UUID: String] = [:]

    public init(
        store: OperatorStore,
        registrationService: RepositoryRegistrationService? = nil
    ) {
        self.store = store
        self.registrationService = registrationService ?? RepositoryRegistrationService(store: store)
    }

    public func loadRepositories() throws {
        let loadedRepositories = try store.repositories()
        repositories = loadedRepositories
        syncDefaultBranchDrafts(with: loadedRepositories)
        errorMessage = nil
    }

    public func loadRepositoriesReportingErrors() {
        do {
            try loadRepositories()
        } catch {
            errorMessage = userFacingMessage(for: error)
        }
    }

    public func addRepository(at repositoryURL: URL) throws {
        _ = try registrationService.registerRepository(at: repositoryURL)
        try loadRepositories()
    }

    public func addRepositoryReportingErrors(at repositoryURL: URL) {
        do {
            try addRepository(at: repositoryURL)
        } catch {
            errorMessage = userFacingMessage(for: error)
        }
    }

    public func updateDefaultBranch(repositoryID: UUID, defaultBranch: String) throws {
        _ = try store.updateRepositoryDefaultBranch(id: repositoryID, defaultBranch: defaultBranch)
        try loadRepositories()
    }

    public func updateDefaultBranchReportingErrors(repositoryID: UUID, defaultBranch: String) {
        do {
            try updateDefaultBranch(repositoryID: repositoryID, defaultBranch: defaultBranch)
        } catch {
            errorMessage = userFacingMessage(for: error)
        }
    }

    func defaultBranchDraft(for repositoryID: UUID) -> String {
        defaultBranchDrafts[repositoryID]
            ?? repositories.first(where: { $0.id == repositoryID })?.defaultBranch
            ?? ""
    }

    func setDefaultBranchDraft(_ defaultBranch: String, for repositoryID: UUID) {
        defaultBranchDrafts[repositoryID] = defaultBranch
        objectWillChange.send()
    }

    private func syncDefaultBranchDrafts(with repositories: [OperatorRepository]) {
        defaultBranchDrafts = Dictionary(
            uniqueKeysWithValues: repositories.map { repository in
                (repository.id, repository.defaultBranch)
            }
        )
    }

    private func userFacingMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let errorDescription = localizedError.errorDescription {
            return errorDescription
        }
        return "Unable to update repository settings."
    }
}
