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
@Test func repositorySettingsModelKeepsListAndShowsRegistrationError() throws {
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

    #expect(model.repositories.map(\.id) == [existingRepository.id])
    #expect(model.errorMessage == "Selected folder is not a Git repository.")
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
