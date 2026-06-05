import Foundation

protocol RepositorySettingsStoring: Sendable {
    func repositories() throws -> [OperatorRepository]
    func updateRepositoryDefaultBranch(id: UUID, defaultBranch: String, now: Date) throws -> OperatorRepository
}

extension OperatorStore: RepositorySettingsStoring {}

@MainActor
public final class RepositorySettingsModel: ObservableObject {
    @Published public private(set) var repositories: [OperatorRepository] = []
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var isAddingRepository = false

    private let store: any RepositorySettingsStoring
    private let registrationService: RepositoryRegistrationService
    private var defaultBranchDrafts: [UUID: String] = [:]

    public init(
        store: OperatorStore,
        registrationService: RepositoryRegistrationService? = nil
    ) {
        self.store = store
        self.registrationService = registrationService ?? RepositoryRegistrationService(store: store)
    }

    init(
        store: any RepositorySettingsStoring,
        registrationService: RepositoryRegistrationService
    ) {
        self.store = store
        self.registrationService = registrationService
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
            errorMessage = Self.userFacingMessage(for: error)
        }
    }

    public func addRepository(at repositoryURL: URL) throws {
        let repository = try registrationService.registerRepository(at: repositoryURL)
        mergeRepository(repository)
        try loadRepositories()
    }

    public func addRepositoryReportingErrors(at repositoryURL: URL) {
        errorMessage = nil
        isAddingRepository = true

        let registrationService = registrationService
        Task { [weak self, registrationService] in
            let completion = await Task.detached(priority: .userInitiated) {
                do {
                    let repository = try registrationService.registerRepository(at: repositoryURL)
                    return RepositoryRegistrationCompletion.success(repository)
                } catch {
                    return RepositoryRegistrationCompletion.failure(Self.userFacingMessage(for: error))
                }
            }.value

            self?.finishRepositoryRegistration(completion)
        }
    }

    public func updateDefaultBranch(repositoryID: UUID, defaultBranch: String) throws {
        let repository = try store.updateRepositoryDefaultBranch(
            id: repositoryID,
            defaultBranch: defaultBranch,
            now: Date()
        )
        mergeRepository(repository)
        try loadRepositories()
    }

    public func updateDefaultBranchReportingErrors(repositoryID: UUID, defaultBranch: String) {
        do {
            try updateDefaultBranch(repositoryID: repositoryID, defaultBranch: defaultBranch)
        } catch {
            errorMessage = Self.userFacingMessage(for: error)
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

    private func mergeRepository(_ repository: OperatorRepository) {
        if let index = repositories.firstIndex(where: { $0.id == repository.id }) {
            repositories[index] = repository
        } else {
            repositories.append(repository)
        }
        defaultBranchDrafts[repository.id] = repository.defaultBranch
    }

    private func finishRepositoryRegistration(_ completion: RepositoryRegistrationCompletion) {
        defer {
            isAddingRepository = false
        }

        switch completion {
        case let .failure(errorMessage):
            self.errorMessage = errorMessage
            return
        case let .success(repository):
            mergeRepository(repository)
        }

        do {
            try loadRepositories()
        } catch {
            self.errorMessage = Self.userFacingMessage(for: error)
        }
    }

    nonisolated private static func userFacingMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let errorDescription = localizedError.errorDescription {
            return errorDescription
        }
        return "Unable to update repository settings."
    }
}

private enum RepositoryRegistrationCompletion: Sendable {
    case success(OperatorRepository)
    case failure(String)
}
