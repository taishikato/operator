import Foundation

public struct PreparedWorktree: Equatable, Sendable {
    public let worktreeURL: URL
    public let baseBranch: String
    public let baseRef: String
    public let gitOriginURL: String?

    public init(worktreeURL: URL, baseBranch: String, baseRef: String, gitOriginURL: String? = nil) {
        self.worktreeURL = worktreeURL
        self.baseBranch = baseBranch
        self.baseRef = baseRef
        self.gitOriginURL = gitOriginURL
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

public struct WorktreePreparer: Sendable {
    private let worktreeRootURL: URL
    private let commandRunner: any CursorGitCommandRunning
    private let attemptIDGenerator: @Sendable () -> UUID

    public init(
        worktreeRootURL: URL = Self.productionWorktreeRootURL(),
        commandRunner: any CursorGitCommandRunning = DefaultCursorGitCommandRunner(),
        attemptIDGenerator: @escaping @Sendable () -> UUID = { UUID() }
    ) {
        self.worktreeRootURL = worktreeRootURL
        self.commandRunner = commandRunner
        self.attemptIDGenerator = attemptIDGenerator
    }

    public static func productionWorktreeRootURL() -> URL {
        URL(filePath: NSHomeDirectory())
            .appending(path: ".codex", directoryHint: .isDirectory)
            .appending(path: "worktrees", directoryHint: .isDirectory)
    }

    public func prepareWorktree(for repository: CursorRepository) throws -> PreparedWorktree {
        let repositoryURL = URL(filePath: repository.localPath).standardizedFileURL
        let baseBranch = repository.defaultBranch
        let baseRef = try resolveBaseRef(repositoryURL: repositoryURL, branch: baseBranch)
        let gitOriginURL = resolveGitOriginURL(repositoryURL: repositoryURL)
        let worktreeURL = codexCompatibleWorktreeURL(
            for: repository,
            repositoryURL: repositoryURL,
            attemptID: attemptIDGenerator()
        )

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
                .worktreePreparerTrimmed
            let actualHead = try commandRunner
                .runGit(repositoryURL: worktreeURL, arguments: ["rev-parse", "HEAD"])
                .worktreePreparerTrimmed

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

        return PreparedWorktree(
            worktreeURL: worktreeURL,
            baseBranch: baseBranch,
            baseRef: baseRef,
            gitOriginURL: gitOriginURL
        )
    }

    private func resolveBaseRef(repositoryURL: URL, branch: String) throws -> String {
        for refName in ["refs/heads/\(branch)", "refs/remotes/origin/\(branch)"] {
            if let baseRef = try? commandRunner
                .runGit(repositoryURL: repositoryURL, arguments: ["rev-parse", refName])
                .worktreePreparerTrimmed,
               !baseRef.isEmpty {
                return baseRef
            }
        }
        throw WorktreePreparationError.unableToResolveBaseBranch(branch: branch)
    }

    private func resolveGitOriginURL(repositoryURL: URL) -> String? {
        guard let originURL = try? commandRunner
            .runGit(repositoryURL: repositoryURL, arguments: ["config", "--get", "remote.origin.url"])
            .worktreePreparerTrimmed,
            !originURL.isEmpty else {
            return repositoryURL.path
        }
        return originURL
    }

    private func codexCompatibleWorktreeURL(
        for repository: CursorRepository,
        repositoryURL: URL,
        attemptID: UUID
    ) -> URL {
        let compactAttemptID = attemptID.uuidString
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
        let repositoryName = normalizedRepositoryDirectoryName(for: repository, repositoryURL: repositoryURL)

        for prefixLength in stride(from: 4, through: compactAttemptID.count, by: 4) {
            let parentName = String(compactAttemptID.prefix(prefixLength))
            let candidate = worktreeRootURL
                .appending(path: parentName, directoryHint: .isDirectory)
                .appending(path: repositoryName, directoryHint: .isDirectory)
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        return worktreeRootURL
            .appending(path: compactAttemptID, directoryHint: .isDirectory)
            .appending(path: repositoryName, directoryHint: .isDirectory)
    }

    private func normalizedRepositoryDirectoryName(
        for repository: CursorRepository,
        repositoryURL: URL
    ) -> String {
        let rawName = repository.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackName = repositoryURL.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = rawName.isEmpty ? fallbackName : rawName
        let normalized = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return normalized.isEmpty ? repository.id.uuidString : normalized
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

public protocol CodexWorktreePreparing: Sendable {
    func prepareWorktree(for repository: CursorRepository) throws -> PreparedWorktree
}

extension WorktreePreparer: CodexWorktreePreparing {}

private extension String {
    var worktreePreparerTrimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
