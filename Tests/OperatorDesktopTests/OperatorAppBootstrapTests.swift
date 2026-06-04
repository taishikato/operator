import Foundation
import Testing
@testable import OperatorDesktop

@Test func appBootstrapInitializesMigratedStoreAtLaunchDatabaseURL() throws {
    let databaseURL = try bootstrapDatabaseURL()

    let store = try OperatorAppBootstrap.initializeStore(databaseURL: databaseURL)
    let repository = try store.createRepository(name: "operator", path: "/tmp/operator", defaultBranch: "main")

    #expect(FileManager.default.fileExists(atPath: databaseURL.path))
    #expect(try store.repositories().map(\.id) == [repository.id])
}

private func bootstrapDatabaseURL() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "OperatorAppBootstrapTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appending(path: "operator.sqlite")
}
