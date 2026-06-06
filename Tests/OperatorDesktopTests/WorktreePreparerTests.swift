import Foundation
import Testing
@testable import OperatorDesktop

@Test func worktreePreparerCreatesDetachedWorktreeFromDefaultBranchAndCapturesBaseRef() throws {
    let repositoryURL = try temporaryDirectory(named: "repo")
    try runGit(["init", "-b", "main"], in: repositoryURL)
    try commitFile(named: "README.md", contents: "base\n", in: repositoryURL)
    let expectedBaseRef = try runGitOutput(["rev-parse", "main"], in: repositoryURL).trimmed
    let appDataURL = try temporaryDirectory(named: "app-data")
    let repository = operatorRepository(path: repositoryURL.path, defaultBranch: "main")

    let prepared = try WorktreePreparer(
        appDataURL: appDataURL,
        attemptIDGenerator: { UUID(uuidString: "11111111-1111-1111-1111-111111111111")! }
    )
    .prepareWorktree(for: repository)

    #expect(prepared.baseBranch == "main")
    #expect(prepared.baseRef == expectedBaseRef)
    #expect(prepared.worktreeURL.path.hasPrefix(appDataURL.appending(path: "worktrees").path))
    #expect(!prepared.worktreeURL.path.hasPrefix(repositoryURL.path + "/"))
    #expect(FileManager.default.fileExists(atPath: prepared.worktreeURL.appending(path: "README.md").path))
    #expect(try runGitOutput(["rev-parse", "--abbrev-ref", "HEAD"], in: prepared.worktreeURL).trimmed == "HEAD")
    #expect(try runGitOutput(["rev-parse", "HEAD"], in: prepared.worktreeURL).trimmed == expectedBaseRef)
    #expect(try runGitOutput(["branch", "--show-current"], in: prepared.worktreeURL).trimmed.isEmpty)
    let branchList = try runGitOutput(
        ["branch", "--list", "11111111-1111-1111-1111-111111111111"],
        in: repositoryURL
    )
    #expect(!branchList.contains("11111111"))
}

@Test func worktreePreparerCreatesFreshPathForEachAttempt() throws {
    let repositoryURL = try temporaryDirectory(named: "repo")
    try runGit(["init", "-b", "main"], in: repositoryURL)
    try commitFile(named: "README.md", contents: "base\n", in: repositoryURL)
    let appDataURL = try temporaryDirectory(named: "app-data")
    let repository = operatorRepository(path: repositoryURL.path, defaultBranch: "main")
    var attemptIDs = [
        UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    ]
    let preparer = WorktreePreparer(appDataURL: appDataURL) {
        attemptIDs.removeFirst()
    }

    let first = try preparer.prepareWorktree(for: repository)
    let second = try preparer.prepareWorktree(for: repository)

    #expect(first.worktreeURL != second.worktreeURL)
    #expect(FileManager.default.fileExists(atPath: first.worktreeURL.path))
    #expect(FileManager.default.fileExists(atPath: second.worktreeURL.path))
}

@Test func worktreePreparerReturnsShortPreparationErrorForMissingBaseBranch() throws {
    let repositoryURL = try temporaryDirectory(named: "repo")
    try runGit(["init", "-b", "main"], in: repositoryURL)
    try commitFile(named: "README.md", contents: "base\n", in: repositoryURL)
    let repository = operatorRepository(path: repositoryURL.path, defaultBranch: "missing")

    #expect(throws: WorktreePreparationError.unableToResolveBaseBranch(branch: "missing")) {
        try WorktreePreparer(appDataURL: temporaryDirectory(named: "app-data"))
            .prepareWorktree(for: repository)
    }

    #expect(
        WorktreePreparationError.unableToResolveBaseBranch(branch: "missing").errorDescription
            == "Unable to prepare worktree from base branch 'missing'."
    )
}

@Test func worktreePreparerFallsBackToRemoteDefaultBranchWhenLocalBranchIsMissing() throws {
    let remoteURL = try temporaryDirectory(named: "origin")
    try runGit(["init", "--bare", "-b", "main"], in: remoteURL)
    let repositoryURL = try temporaryDirectory(named: "repo")
    try runGit(["init", "-b", "main"], in: repositoryURL)
    try commitFile(named: "README.md", contents: "base\n", in: repositoryURL)
    try runGit(["remote", "add", "origin", remoteURL.path], in: repositoryURL)
    try runGit(["push", "-u", "origin", "main"], in: repositoryURL)
    try runGit(["switch", "-c", "feature"], in: repositoryURL)
    try runGit(["branch", "-D", "main"], in: repositoryURL)
    let expectedBaseRef = try runGitOutput(["rev-parse", "refs/remotes/origin/main"], in: repositoryURL).trimmed
    let repository = operatorRepository(path: repositoryURL.path, defaultBranch: "main")

    let prepared = try WorktreePreparer(appDataURL: temporaryDirectory(named: "app-data"))
        .prepareWorktree(for: repository)

    #expect(prepared.baseRef == expectedBaseRef)
    #expect(try runGitOutput(["rev-parse", "--abbrev-ref", "HEAD"], in: prepared.worktreeURL).trimmed == "HEAD")
    #expect(try runGitOutput(["rev-parse", "HEAD"], in: prepared.worktreeURL).trimmed == expectedBaseRef)
}

@Test func worktreePreparerDoesNotRunNetworkHistoryMutationOrSetupCommands() throws {
    let runner = RecordingWorktreeGitCommandRunner(outputs: [
        ["rev-parse", "refs/heads/main"]: "abc123\n",
        ["worktree", "add", "--detach", "/tmp/operator/worktrees/AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA/11111111-1111-1111-1111-111111111111", "abc123"]: "",
        ["rev-parse", "--abbrev-ref", "HEAD"]: "HEAD\n",
        ["rev-parse", "HEAD"]: "abc123\n"
    ])
    let repository = operatorRepository(id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!, path: "/tmp/repo", defaultBranch: "main")

    _ = try WorktreePreparer(
        appDataURL: URL(filePath: "/tmp/operator"),
        commandRunner: runner,
        attemptIDGenerator: { UUID(uuidString: "11111111-1111-1111-1111-111111111111")! }
    )
    .prepareWorktree(for: repository)

    let forbidden = Set(["fetch", "pull", "merge", "rebase", "install", "setup"])
    #expect(runner.commands.allSatisfy { command in
        command.arguments.allSatisfy { !forbidden.contains($0) }
    })
}

@Test func worktreePreparerRemovesCreatedWorktreeWhenVerificationFails() throws {
    let worktreePath = "/tmp/operator/worktrees/AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA/11111111-1111-1111-1111-111111111111"
    let runner = RecordingWorktreeGitCommandRunner(outputs: [
        ["rev-parse", "refs/heads/main"]: "abc123\n",
        ["worktree", "add", "--detach", worktreePath, "abc123"]: "",
        ["rev-parse", "--abbrev-ref", "HEAD"]: "main\n",
        ["worktree", "remove", "--force", worktreePath]: ""
    ])
    let repository = operatorRepository(id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!, path: "/tmp/repo", defaultBranch: "main")

    #expect(throws: WorktreePreparationError.unableToCreateWorktree) {
        try WorktreePreparer(
            appDataURL: URL(filePath: "/tmp/operator"),
            commandRunner: runner,
            attemptIDGenerator: { UUID(uuidString: "11111111-1111-1111-1111-111111111111")! }
        )
        .prepareWorktree(for: repository)
    }

    #expect(runner.commands.contains(.init(repositoryURL: URL(filePath: "/tmp/repo"), arguments: [
        "worktree", "remove", "--force", worktreePath
    ])))
}

private final class RecordingWorktreeGitCommandRunner: GitCommandRunning, @unchecked Sendable {
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
        throw RepositoryRegistrationError.gitCommandFailed
    }
}

private func operatorRepository(
    id: UUID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
    path: String,
    defaultBranch: String
) -> OperatorRepository {
    OperatorRepository(
        id: id,
        name: "repo",
        path: path,
        defaultBranch: defaultBranch,
        createdAt: Date(timeIntervalSince1970: 0),
        updatedAt: Date(timeIntervalSince1970: 0)
    )
}

private func temporaryDirectory(named name: String) throws -> URL {
    let directoryURL = FileManager.default.temporaryDirectory
        .appending(path: "WorktreePreparerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        .appending(path: name, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    return directoryURL
}

private func commitFile(named name: String, contents: String, in repositoryURL: URL) throws {
    try contents.write(to: repositoryURL.appending(path: name), atomically: true, encoding: .utf8)
    try runGit(["add", name], in: repositoryURL)
    try runGit(
        [
            "-c", "user.name=Operator",
            "-c", "user.email=operator@example.test",
            "commit", "-m", "Add \(name)"
        ],
        in: repositoryURL
    )
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
            domain: "WorktreePreparerTests",
            code: Int(process.terminationStatus),
            userInfo: [NSLocalizedDescriptionKey: error]
        )
    }
}

private func runGitOutput(_ arguments: [String], in directoryURL: URL?) throws -> String {
    let process = Process()
    process.executableURL = URL(filePath: "/usr/bin/git")
    process.arguments = arguments
    process.currentDirectoryURL = directoryURL

    let outputPipe = Pipe()
    let errorPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = errorPipe

    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        let error = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        throw NSError(
            domain: "WorktreePreparerTests",
            code: Int(process.terminationStatus),
            userInfo: [NSLocalizedDescriptionKey: error]
        )
    }

    return String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
