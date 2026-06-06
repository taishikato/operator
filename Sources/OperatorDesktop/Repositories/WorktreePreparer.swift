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
        let baseRef: String
        do {
            baseRef = try commandRunner
                .runGit(repositoryURL: repositoryURL, arguments: ["rev-parse", "refs/heads/\(baseBranch)"])
                .trimmedForWorktreePreparation
        } catch {
            throw WorktreePreparationError.unableToResolveBaseBranch(branch: baseBranch)
        }

        guard !baseRef.isEmpty else {
            throw WorktreePreparationError.unableToResolveBaseBranch(branch: baseBranch)
        }

        let worktreeURL = appDataURL
            .appending(path: "worktrees", directoryHint: .isDirectory)
            .appending(path: repository.id.uuidString, directoryHint: .isDirectory)
            .appending(path: attemptIDGenerator().uuidString, directoryHint: .isDirectory)

        do {
            try FileManager.default.createDirectory(
                at: worktreeURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            _ = try commandRunner.runGit(
                repositoryURL: repositoryURL,
                arguments: ["worktree", "add", "--detach", worktreeURL.path, baseRef]
            )

            let branchName = try commandRunner
                .runGit(repositoryURL: worktreeURL, arguments: ["rev-parse", "--abbrev-ref", "HEAD"])
                .trimmedForWorktreePreparation
            let actualHead = try commandRunner
                .runGit(repositoryURL: worktreeURL, arguments: ["rev-parse", "HEAD"])
                .trimmedForWorktreePreparation

            guard branchName == "HEAD", actualHead == baseRef else {
                throw WorktreePreparationError.unableToCreateWorktree
            }
        } catch let error as WorktreePreparationError {
            throw error
        } catch {
            throw WorktreePreparationError.unableToCreateWorktree
        }

        return PreparedWorktree(worktreeURL: worktreeURL, baseBranch: baseBranch, baseRef: baseRef)
    }
}

private extension String {
    var trimmedForWorktreePreparation: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
