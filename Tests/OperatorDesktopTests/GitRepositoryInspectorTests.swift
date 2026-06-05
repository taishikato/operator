import Foundation
import Testing
@testable import OperatorDesktop

@Test func gitInspectorAcceptsRepositoryAndInfersNameAndCurrentBranch() throws {
    let repositoryURL = try temporaryDirectory(named: "operator")
    try runGit(["init", "-b", "feature/desktop"], in: repositoryURL)

    let inspection = try GitRepositoryInspector().inspect(repositoryURL)

    #expect(inspection.name == "operator")
    #expect(inspection.path == repositoryURL.standardizedFileURL.path)
    #expect(inspection.defaultBranch == "feature/desktop")
}

@Test func gitInspectorRejectsNonRepositoryWithUserFacingError() throws {
    let directoryURL = try temporaryDirectory(named: "not-a-repo")

    #expect(throws: RepositoryRegistrationError.invalidGitRepository(path: directoryURL.path)) {
        try GitRepositoryInspector().inspect(directoryURL)
    }

    let error = RepositoryRegistrationError.invalidGitRepository(path: directoryURL.path)
    #expect(error.errorDescription == "Selected folder is not a Git repository.")
}

@Test func gitInspectorUsesLocalOriginHeadWhenAvailable() throws {
    let remoteURL = try temporaryDirectory(named: "remote")
    try runGit(["init", "--bare", "--initial-branch=develop"], in: remoteURL)

    let repositoryURL = try temporaryDirectory(named: "with-origin")
    try runGit(["clone", remoteURL.path, repositoryURL.path], in: nil)
    try runGit(["symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/develop"], in: repositoryURL)

    let inspection = try GitRepositoryInspector().inspect(repositoryURL)

    #expect(inspection.defaultBranch == "develop")
}

@Test func gitInspectorDoesNotRunNetworkOrHistoryMutatingCommands() throws {
    let runner = RecordingGitCommandRunner(outputs: [
        ["rev-parse", "--show-toplevel"]: "/tmp/operator\n",
        ["symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD"]: "",
        ["branch", "--show-current"]: "main\n"
    ])
    let inspector = GitRepositoryInspector(commandRunner: runner)

    _ = try inspector.inspect(URL(filePath: "/tmp/operator"))

    let forbidden = Set(["fetch", "pull", "merge", "rebase"])
    #expect(runner.commands.allSatisfy { command in
        command.arguments.allSatisfy { !forbidden.contains($0) }
    })
}

@Test func defaultGitCommandRunnerCompletesWhenGitWritesLargeOutput() async throws {
    let repositoryURL = try temporaryDirectory(named: "many-branches")
    try runGit(["init", "-b", "main"], in: repositoryURL)
    try runGit(
        [
            "-c", "user.name=Operator",
            "-c", "user.email=operator@example.test",
            "commit", "--allow-empty", "-m", "init"
        ],
        in: repositoryURL
    )
    let head = try runGitOutput(["rev-parse", "HEAD"], in: repositoryURL)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let refsURL = repositoryURL.appending(path: ".git/refs/heads", directoryHint: .isDirectory)
    for index in 0..<4_000 {
        let branchName = "branch-\(index)-\(String(repeating: "x", count: 80))"
        try head.write(
            to: refsURL.appending(path: branchName),
            atomically: true,
            encoding: .utf8
        )
    }

    let output = try await runGitWithTimeout(
        repositoryURL: repositoryURL,
        arguments: ["for-each-ref", "--format=%(refname:short)", "refs/heads"]
    )

    #expect(output.contains("branch-3999"))
}

private final class RecordingGitCommandRunner: GitCommandRunning, @unchecked Sendable {
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

private func temporaryDirectory(named name: String) throws -> URL {
    let directoryURL = FileManager.default.temporaryDirectory
        .appending(path: "GitRepositoryInspectorTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        .appending(path: name, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    return directoryURL
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
            domain: "GitRepositoryInspectorTests",
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
            domain: "GitRepositoryInspectorTests",
            code: Int(process.terminationStatus),
            userInfo: [NSLocalizedDescriptionKey: error]
        )
    }

    return String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
}

private func runGitWithTimeout(repositoryURL: URL, arguments: [String]) async throws -> String {
    enum Completion: Sendable {
        case output(String)
        case failure(String)
        case timedOut
    }

    let commandTask = Task.detached {
        do {
            return Completion.output(
                try DefaultGitCommandRunner().runGit(repositoryURL: repositoryURL, arguments: arguments)
            )
        } catch {
            return Completion.failure(String(describing: error))
        }
    }

    let completion = await withTaskGroup(of: Completion.self) { group in
        group.addTask {
            await commandTask.value
        }
        group.addTask {
            try? await Task.sleep(for: .seconds(5))
            return .timedOut
        }

        let firstCompletion = await group.next() ?? .timedOut
        group.cancelAll()
        return firstCompletion
    }

    switch completion {
    case let .output(output):
        return output
    case let .failure(message):
        throw NSError(
            domain: "GitRepositoryInspectorTests",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    case .timedOut:
        throw NSError(
            domain: "GitRepositoryInspectorTests",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for git output."]
        )
    }
}
