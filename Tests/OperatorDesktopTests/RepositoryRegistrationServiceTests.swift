import Foundation
import Testing
@testable import OperatorDesktop

@Test func registrationServicePersistsInspectedRepository() throws {
    let store = try OperatorStore(databaseURL: temporaryRegistrationDatabaseURL())
    let repositoryURL = URL(filePath: "/tmp/operator")
    let inspector = StubRepositoryInspector(
        inspection: RepositoryInspection(
            name: "operator",
            path: repositoryURL.path,
            defaultBranch: "feature/desktop"
        )
    )
    let service = RepositoryRegistrationService(store: store, inspector: inspector)
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    let repository = try service.registerRepository(at: repositoryURL, now: now)

    #expect(repository.name == "operator")
    #expect(repository.path == repositoryURL.path)
    #expect(repository.defaultBranch == "feature/desktop")
    #expect(try store.repositories() == [repository])
}

@Test func registrationServicePersistsEmptyDefaultBranchWhenGitCannotInferOne() throws {
    let store = try OperatorStore(databaseURL: temporaryRegistrationDatabaseURL())
    let repositoryURL = URL(filePath: "/tmp/operator")
    let inspector = StubRepositoryInspector(
        inspection: RepositoryInspection(name: "operator", path: repositoryURL.path, defaultBranch: nil)
    )
    let service = RepositoryRegistrationService(store: store, inspector: inspector)

    let repository = try service.registerRepository(at: repositoryURL)

    #expect(repository.defaultBranch == "")
}

@Test func registrationServiceSurfacesInvalidRepositoryErrors() throws {
    let store = try OperatorStore(databaseURL: temporaryRegistrationDatabaseURL())
    let repositoryURL = URL(filePath: "/tmp/not-a-repo")
    let inspector = StubRepositoryInspector(error: .invalidGitRepository(path: repositoryURL.path))
    let service = RepositoryRegistrationService(store: store, inspector: inspector)

    #expect(throws: RepositoryRegistrationError.invalidGitRepository(path: repositoryURL.path)) {
        try service.registerRepository(at: repositoryURL)
    }
    #expect(try store.repositories().isEmpty)
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

private func temporaryRegistrationDatabaseURL() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "RepositoryRegistrationServiceTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appending(path: "operator.sqlite")
}
