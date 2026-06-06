import Foundation

public struct PreparedWorktree: Equatable, Sendable {
    public let worktreeURL: URL
    public let baseBranch: String
    public let baseRef: String

    public init(worktreeURL: URL, baseBranch: String, baseRef: String) {
        self.worktreeURL = worktreeURL
        self.baseBranch = baseBranch
        self.baseRef = baseRef
    }
}

public enum WorktreePreparationError: Error, Equatable, LocalizedError, Sendable {
    case unableToResolveBaseBranch(branch: String)
    case unableToCreateWorktree

    public var errorDescription: String? {
        switch self {
        case let .unableToResolveBaseBranch(branch):
            "Unable to prepare worktree from base branch '\(branch)'."
        case .unableToCreateWorktree:
            "Unable to prepare worktree."
        }
    }
}

public struct WorktreePreparer {
    private let appDataURL: URL
    private let commandRunner: any GitCommandRunning
    private let attemptIDGenerator: () -> UUID

    public init(
        appDataURL: URL,
        commandRunner: any GitCommandRunning = DefaultGitCommandRunner(),
        attemptIDGenerator: @escaping () -> UUID = { UUID() }
    ) {
        self.appDataURL = appDataURL
        self.commandRunner = commandRunner
        self.attemptIDGenerator = attemptIDGenerator
    }

    public func prepareWorktree(for repository: OperatorRepository) throws -> PreparedWorktree {
        let repositoryURL = URL(filePath: repository.path).standardizedFileURL
        let baseBranch = repository.defaultBranch
        let baseRef = try resolveBaseRef(repositoryURL: repositoryURL, branch: baseBranch)
        let worktreeURL = appDataURL
            .appending(path: "worktrees", directoryHint: .isDirectory)
            .appending(path: repository.id.uuidString, directoryHint: .isDirectory)
            .appending(path: attemptIDGenerator().uuidString, directoryHint: .isDirectory)

        var didCreateWorktree = false
        do {
            try FileManager.default.createDirectory(
                at: worktreeURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            _ = try commandRunner.runGit(
                repositoryURL: repositoryURL,
                arguments: ["worktree", "add", "--detach", worktreeURL.path, baseRef]
            )
            didCreateWorktree = true

            let branchName = try commandRunner
                .runGit(repositoryURL: worktreeURL, arguments: ["rev-parse", "--abbrev-ref", "HEAD"])
                .trimmed
            let actualHead = try commandRunner
                .runGit(repositoryURL: worktreeURL, arguments: ["rev-parse", "HEAD"])
                .trimmed

            guard branchName == "HEAD", actualHead == baseRef else {
                throw WorktreePreparationError.unableToCreateWorktree
            }
        } catch let error as WorktreePreparationError {
            if didCreateWorktree {
                cleanupCreatedWorktree(repositoryURL: repositoryURL, worktreeURL: worktreeURL)
            }
            throw error
        } catch {
            if didCreateWorktree {
                cleanupCreatedWorktree(repositoryURL: repositoryURL, worktreeURL: worktreeURL)
            }
            throw WorktreePreparationError.unableToCreateWorktree
        }

        return PreparedWorktree(worktreeURL: worktreeURL, baseBranch: baseBranch, baseRef: baseRef)
    }

    private func resolveBaseRef(repositoryURL: URL, branch: String) throws -> String {
        for refName in ["refs/heads/\(branch)", "refs/remotes/origin/\(branch)"] {
            if let baseRef = try? commandRunner
                .runGit(repositoryURL: repositoryURL, arguments: ["rev-parse", refName])
                .trimmed,
                !baseRef.isEmpty {
                return baseRef
            }
        }
        throw WorktreePreparationError.unableToResolveBaseBranch(branch: branch)
    }

    private func cleanupCreatedWorktree(repositoryURL: URL, worktreeURL: URL) {
        _ = try? commandRunner.runGit(
            repositoryURL: repositoryURL,
            arguments: ["worktree", "remove", "--force", worktreeURL.path]
        )
        if FileManager.default.fileExists(atPath: worktreeURL.path) {
            try? FileManager.default.removeItem(at: worktreeURL)
        }
    }
}

extension WorktreePreparer: CodexWorktreePreparing {}
