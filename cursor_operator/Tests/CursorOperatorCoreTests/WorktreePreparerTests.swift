import Foundation
import Testing
@testable import CursorOperatorCore

@Test func worktreePreparerUsesCodexCompatibleWorktreePathShape() throws {
    let runner = RecordingWorktreeGitCommandRunner(outputs: [
        ["rev-parse", "refs/heads/main"]: "abc123\n",
        ["config", "--get", "remote.origin.url"]: "git@github.com:taishikato/operator.git\n",
        ["worktree", "add", "--detach", "/tmp/codex-worktrees/1234/operator", "abc123"]: "",
        ["rev-parse", "--abbrev-ref", "HEAD"]: "HEAD\n",
        ["rev-parse", "HEAD"]: "abc123\n"
    ])
    let repository = CursorRepository(
        id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
        name: "operator",
        localPath: "/tmp/operator",
        githubURL: URL(string: "https://github.com/taishikato/operator")!,
        defaultBranch: "main",
        createdAt: Date(timeIntervalSince1970: 0),
        updatedAt: Date(timeIntervalSince1970: 0)
    )

    let prepared = try WorktreePreparer(
        worktreeRootURL: URL(filePath: "/tmp/codex-worktrees"),
        commandRunner: runner,
        attemptIDGenerator: { UUID(uuidString: "12345678-1111-2222-3333-444444444444")! }
    )
    .prepareWorktree(for: repository)

    #expect(prepared.worktreeURL.path == "/tmp/codex-worktrees/1234/operator")
    #expect(prepared.baseBranch == "main")
    #expect(prepared.baseRef == "abc123")
    #expect(prepared.gitOriginURL == "git@github.com:taishikato/operator.git")
    #expect(runner.commands.contains(.init(repositoryURL: URL(filePath: "/tmp/operator"), arguments: [
        "worktree", "add", "--detach", "/tmp/codex-worktrees/1234/operator", "abc123"
    ])))
}

private final class RecordingWorktreeGitCommandRunner: CursorGitCommandRunning, @unchecked Sendable {
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
