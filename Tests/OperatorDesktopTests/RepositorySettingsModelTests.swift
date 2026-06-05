import Foundation
import Testing
@testable import OperatorDesktop

@MainActor
@Test func repositorySettingsModelLoadsAndUpdatesDefaultBranch() throws {
    let store = try OperatorStore(databaseURL: temporarySettingsDatabaseURL())
    let repository = try store.createRepository(name: "operator", path: "/tmp/operator", defaultBranch: "main")
    let model = RepositorySettingsModel(store: store)

    try model.loadRepositories()
    try model.updateDefaultBranch(repositoryID: repository.id, defaultBranch: "feature/desktop")

    #expect(model.repositories.map(\.id) == [repository.id])
    #expect(model.repositories.first?.defaultBranch == "feature/desktop")
    #expect(model.errorMessage == nil)
}

@MainActor
@Test func repositorySettingsModelKeepsUpdatedBranchWhenReloadFailsAfterWrite() throws {
    let repository = OperatorRepository(
        id: UUID(),
        name: "operator",
        path: "/tmp/operator",
        defaultBranch: "main",
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let store = ReloadFailingSettingsStore(repositories: [repository])
    let registrationStore = try OperatorStore(databaseURL: temporarySettingsDatabaseURL())
    let model = RepositorySettingsModel(
        store: store,
        registrationService: RepositoryRegistrationService(store: registrationStore)
    )

    try model.loadRepositories()
    store.failReads = true

    #expect(throws: SettingsStoreError.reloadFailed) {
        try model.updateDefaultBranch(repositoryID: repository.id, defaultBranch: "develop")
    }
    #expect(model.repositories.first?.defaultBranch == "develop")
}

@MainActor
@Test func repositorySettingsModelResyncsDefaultBranchDraftsWhenRepositoriesReload() throws {
    let store = try OperatorStore(databaseURL: temporarySettingsDatabaseURL())
    let repository = try store.createRepository(name: "operator", path: "/tmp/operator", defaultBranch: "main")
    let model = RepositorySettingsModel(store: store)

    try model.loadRepositories()
    model.setDefaultBranchDraft("typed-but-not-saved", for: repository.id)
    _ = try store.updateRepositoryDefaultBranch(id: repository.id, defaultBranch: "develop")

    try model.loadRepositories()

    #expect(model.defaultBranchDraft(for: repository.id) == "develop")
}

@MainActor
@Test func repositorySettingsModelRegistersRepositoryAndReloadsList() throws {
    let store = try OperatorStore(databaseURL: temporarySettingsDatabaseURL())
    let repositoryURL = URL(filePath: "/tmp/operator")
    let service = RepositoryRegistrationService(
        store: store,
        inspector: StubRepositoryInspector(
            inspection: RepositoryInspection(name: "operator", path: repositoryURL.path, defaultBranch: "main")
        )
    )
    let model = RepositorySettingsModel(store: store, registrationService: service)

    try model.addRepository(at: repositoryURL)

    #expect(model.repositories.map(\.name) == ["operator"])
    #expect(model.repositories.first?.defaultBranch == "main")
    #expect(model.errorMessage == nil)
}

@MainActor
@Test func repositorySettingsModelStartsRepositoryRegistrationWithoutBlockingMainActor() async throws {
    let store = try OperatorStore(databaseURL: temporarySettingsDatabaseURL())
    let repositoryURL = URL(filePath: "/tmp/operator")
    let service = RepositoryRegistrationService(
        store: store,
        inspector: SlowRepositoryInspector(
            inspection: RepositoryInspection(name: "operator", path: repositoryURL.path, defaultBranch: "main")
        )
    )
    let model = RepositorySettingsModel(store: store, registrationService: service)

    let startedAt = Date()
    model.addRepositoryReportingErrors(at: repositoryURL)
    let elapsed = Date().timeIntervalSince(startedAt)

    #expect(elapsed < 0.1)
    try await waitUntil {
        model.repositories.map(\.name) == ["operator"]
    }
    #expect(model.errorMessage == nil)
}

@MainActor
@Test func repositorySettingsModelKeepsListAndShowsRegistrationError() async throws {
    let store = try OperatorStore(databaseURL: temporarySettingsDatabaseURL())
    let existingRepository = try store.createRepository(name: "operator", path: "/tmp/operator", defaultBranch: "main")
    let invalidURL = URL(filePath: "/tmp/not-a-repo")
    let service = RepositoryRegistrationService(
        store: store,
        inspector: StubRepositoryInspector(error: .invalidGitRepository(path: invalidURL.path))
    )
    let model = RepositorySettingsModel(store: store, registrationService: service)

    model.loadRepositoriesReportingErrors()
    model.addRepositoryReportingErrors(at: invalidURL)

    try await waitUntil {
        model.errorMessage == "Selected folder is not a Git repository."
    }
    #expect(model.repositories.map(\.id) == [existingRepository.id])
    #expect(model.isAddingRepository == false)
}

private struct SlowRepositoryInspector: RepositoryInspecting {
    let inspection: RepositoryInspection

    func inspect(_ repositoryURL: URL) throws -> RepositoryInspection {
        Thread.sleep(forTimeInterval: 0.3)
        return inspection
    }
}

private final class ReloadFailingSettingsStore: RepositorySettingsStoring, @unchecked Sendable {
    var repositoriesValue: [OperatorRepository]
    var failReads = false

    init(repositories: [OperatorRepository]) {
        repositoriesValue = repositories
    }

    func repositories() throws -> [OperatorRepository] {
        if failReads {
            throw SettingsStoreError.reloadFailed
        }
        return repositoriesValue
    }

    func updateRepositoryDefaultBranch(
        id: UUID,
        defaultBranch: String,
        now: Date
    ) throws -> OperatorRepository {
        guard let index = repositoriesValue.firstIndex(where: { $0.id == id }) else {
            throw OperatorStoreError.repositoryNotFound
        }
        let existingRepository = repositoriesValue[index]
        let updatedRepository = OperatorRepository(
            id: existingRepository.id,
            name: existingRepository.name,
            path: existingRepository.path,
            defaultBranch: defaultBranch,
            createdAt: existingRepository.createdAt,
            updatedAt: now
        )
        repositoriesValue[index] = updatedRepository
        return updatedRepository
    }
}

private enum SettingsStoreError: Error, Equatable {
    case reloadFailed
}

private struct StubRepositoryInspector: RepositoryInspecting {
    let inspection: RepositoryInspection?
    let error: RepositoryRegistrationError?

    init(inspection: RepositoryInspection) {
        self.inspection = inspection
        error = nil
    }

    init(error: RepositoryRegistrationError) {
        inspection = nil
        self.error = error
    }

    func inspect(_ repositoryURL: URL) throws -> RepositoryInspection {
        if let error {
            throw error
        }
        return inspection!
    }
}

private func temporarySettingsDatabaseURL() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "RepositorySettingsModelTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appending(path: "operator.sqlite")
}

@MainActor
private func waitUntil(
    timeout: Duration = .seconds(2),
    condition: @escaping @MainActor () -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while !condition() {
        if clock.now >= deadline {
            throw NSError(
                domain: "RepositorySettingsModelTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for condition."]
            )
        }
        try await Task.sleep(for: .milliseconds(10))
    }
}
