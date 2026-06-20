import Foundation
import Testing
@testable import CursorOperatorCore

@Test func cursorGitInspectorAcceptsGitHubHTTPSOriginAndInfersCurrentBranch() throws {
    let repositoryURL = try temporaryGitDirectory(named: "operator")
    try runGit(["init", "-b", "feature/cursor"], in: repositoryURL)
    try runGit(["remote", "add", "origin", "https://github.com/example/operator.git"], in: repositoryURL)

    let inspection = try CursorGitRepositoryInspector().inspect(repositoryURL)

    #expect(inspection.name == "operator")
    #expect(inspection.localPath == repositoryURL.standardizedFileURL.path)
    #expect(inspection.githubURL == URL(string: "https://github.com/example/operator")!)
    #expect(inspection.defaultBranch == "feature/cursor")
}

@Test func cursorGitInspectorNormalizesGitHubSSHOrigin() throws {
    let repositoryURL = try temporaryGitDirectory(named: "ssh-origin")
    try runGit(["init", "-b", "main"], in: repositoryURL)
    try runGit(["remote", "add", "origin", "git@github.com:example/operator.git"], in: repositoryURL)

    let inspection = try CursorGitRepositoryInspector().inspect(repositoryURL)

    #expect(inspection.githubURL == URL(string: "https://github.com/example/operator")!)
}

@Test func cursorGitInspectorRejectsNonRepositoryMissingOriginAndUnsupportedRemotes() throws {
    let nonRepositoryURL = try temporaryDirectory(named: "not-a-repo")
    #expect(throws: CursorRepositoryRegistrationError.invalidGitRepository(path: nonRepositoryURL.path)) {
        try CursorGitRepositoryInspector().inspect(nonRepositoryURL)
    }

    let missingOriginURL = try temporaryGitDirectory(named: "missing-origin")
    try runGit(["init", "-b", "main"], in: missingOriginURL)
    #expect(throws: CursorRepositoryRegistrationError.missingGitHubOrigin) {
        try CursorGitRepositoryInspector().inspect(missingOriginURL)
    }

    let unsupportedURL = try temporaryGitDirectory(named: "unsupported-origin")
    try runGit(["init", "-b", "main"], in: unsupportedURL)
    try runGit(["remote", "add", "origin", "https://gitlab.com/example/operator.git"], in: unsupportedURL)
    #expect(throws: CursorRepositoryRegistrationError.unsupportedRemoteURL("https://gitlab.com/example/operator.git")) {
        try CursorGitRepositoryInspector().inspect(unsupportedURL)
    }
}

@Test func cursorGitInspectorUsesRemoteOriginHeadWhenAvailable() throws {
    let runner = RecordingCursorGitCommandRunner(outputs: [
        ["rev-parse", "--show-toplevel"]: "/tmp/operator\n",
        ["config", "--get", "remote.origin.url"]: "https://github.com/example/operator.git\n",
        ["symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD"]: "origin/develop\n"
    ])
    let inspector = CursorGitRepositoryInspector(commandRunner: runner)

    let inspection = try inspector.inspect(URL(filePath: "/tmp/operator"))

    #expect(inspection.defaultBranch == "develop")
}

@Test func cursorGitInspectorDoesNotRunGitNetworkOrHistoryMutatingCommands() throws {
    let runner = RecordingCursorGitCommandRunner(outputs: [
        ["rev-parse", "--show-toplevel"]: "/tmp/operator\n",
        ["config", "--get", "remote.origin.url"]: "https://github.com/example/operator.git\n",
        ["symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD"]: "",
        ["branch", "--show-current"]: "main\n"
    ])
    let inspector = CursorGitRepositoryInspector(commandRunner: runner)

    _ = try inspector.inspect(URL(filePath: "/tmp/operator"))

    let forbidden = Set(["fetch", "pull", "push", "merge", "rebase"])
    #expect(runner.commands.allSatisfy { command in
        command.arguments.allSatisfy { !forbidden.contains($0) }
    })
}

@Test func registrationServiceSavesReviewedAndEditedDefaultBranch() throws {
    let store = try CursorOperatorStore(databaseURL: temporaryGitRegistrationDatabaseURL())
    let repositoryURL = URL(filePath: "/tmp/operator")
    let inspector = StubCursorRepositoryInspector(
        inspection: CursorRepositoryInspection(
            name: "operator",
            localPath: repositoryURL.path,
            githubURL: URL(string: "https://github.com/example/operator")!,
            defaultBranch: "main"
        )
    )
    let service = CursorRepositoryRegistrationService(store: store, inspector: inspector)

    let draft = try service.prepareRepository(at: repositoryURL)
    let repository = try service.saveRepository(draft, defaultBranch: "trunk")

    #expect(draft.defaultBranch == "main")
    #expect(repository.defaultBranch == "trunk")
    #expect(repository.githubURL == URL(string: "https://github.com/example/operator")!)
    #expect(repository.localPath == repositoryURL.path)
    #expect(try store.repositories().map(\.id) == [repository.id])
}

private final class RecordingCursorGitCommandRunner: CursorGitCommandRunning, @unchecked Sendable {
    struct Command: Equatable {
        let repositoryURL: URL?
        let arguments: [String]
    }

    private let outputs: [[String]: String]
    private(set) var commands: [Command] = []

    init(outputs: [[String]: String]) {
        self.outputs = outputs
    }

    func runGit(repositoryURL: URL?, arguments: [String]) throws -> String {
        commands.append(Command(repositoryURL: repositoryURL, arguments: arguments))
        if let output = outputs[arguments] {
            return output
        }
        throw CursorRepositoryRegistrationError.gitCommandFailed
    }
}

private struct StubCursorRepositoryInspector: CursorRepositoryInspecting {
    let inspection: CursorRepositoryInspection

    func inspect(_ repositoryURL: URL) throws -> CursorRepositoryInspection {
        inspection
    }
}

private func temporaryGitDirectory(named name: String) throws -> URL {
    try temporaryDirectory(named: name)
}

private func temporaryDirectory(named name: String) throws -> URL {
    let directoryURL = FileManager.default.temporaryDirectory
        .appending(path: "CursorGitRepositoryInspectorTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        .appending(path: name, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    return directoryURL
}

private func temporaryGitRegistrationDatabaseURL() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "CursorRepositoryRegistrationTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appending(path: "cursor-operator.sqlite")
}

private func runGit(_ arguments: [String], in directoryURL: URL?) throws {
    let process = Process()
    process.executableURL = URL(filePath: "/usr/bin/git")
    process.arguments = arguments
    process.currentDirectoryURL = directoryURL

    let errorPipe = Pipe()
    process.standardError = errorPipe

    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        let error = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        throw NSError(
            domain: "CursorGitRepositoryInspectorTests",
            code: Int(process.terminationStatus),
            userInfo: [NSLocalizedDescriptionKey: error]
        )
    }
}
