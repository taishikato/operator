import Foundation

public struct RepositoryInspection: Equatable, Sendable {
    public let name: String
    public let path: String
    public let defaultBranch: String?

    public init(name: String, path: String, defaultBranch: String?) {
        self.name = name
        self.path = path
        self.defaultBranch = defaultBranch
    }
}

public enum RepositoryRegistrationError: Error, Equatable, LocalizedError, Sendable {
    case invalidGitRepository(path: String)
    case gitCommandFailed

    public var errorDescription: String? {
        switch self {
        case .invalidGitRepository:
            "Selected folder is not a Git repository."
        case .gitCommandFailed:
            "Unable to inspect the selected Git repository."
        }
    }
}

public protocol RepositoryInspecting: Sendable {
    func inspect(_ repositoryURL: URL) throws -> RepositoryInspection
}

public protocol GitCommandRunning: AnyObject, Sendable {
    func runGit(repositoryURL: URL?, arguments: [String]) throws -> String
}

public struct GitRepositoryInspector: RepositoryInspecting, Sendable {
    private let commandRunner: any GitCommandRunning

    public init(commandRunner: any GitCommandRunning = DefaultGitCommandRunner()) {
        self.commandRunner = commandRunner
    }

    public func inspect(_ repositoryURL: URL) throws -> RepositoryInspection {
        let rootPath: String
        do {
            rootPath = try commandRunner
                .runGit(repositoryURL: repositoryURL, arguments: ["rev-parse", "--show-toplevel"])
                .trimmed
        } catch {
            throw RepositoryRegistrationError.invalidGitRepository(path: repositoryURL.path)
        }

        guard !rootPath.isEmpty else {
            throw RepositoryRegistrationError.invalidGitRepository(path: repositoryURL.path)
        }

        let rootURL = URL(filePath: rootPath).standardizedFileURL
        return RepositoryInspection(
            name: rootURL.lastPathComponent,
            path: rootURL.path,
            defaultBranch: try inferDefaultBranch(repositoryURL: rootURL)
        )
    }

    private func inferDefaultBranch(repositoryURL: URL) throws -> String? {
        if let originHead = try? commandRunner.runGit(
            repositoryURL: repositoryURL,
            arguments: ["symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD"]
        ).trimmed,
            let branch = branchName(fromOriginHead: originHead) {
            return branch
        }

        let currentBranch = try commandRunner.runGit(
            repositoryURL: repositoryURL,
            arguments: ["branch", "--show-current"]
        ).trimmed
        if !currentBranch.isEmpty {
            return currentBranch
        }

        let branches = try commandRunner.runGit(
            repositoryURL: repositoryURL,
            arguments: ["for-each-ref", "--format=%(refname:short)", "refs/heads"]
        )
        .split(whereSeparator: \.isNewline)
        .map(String.init)
        if !branches.isEmpty {
            return branches.first(where: { $0 == "main" })
                ?? branches.first(where: { $0 == "master" })
                ?? branches.first
        }

        return nil
    }

    private func branchName(fromOriginHead originHead: String) -> String? {
        guard !originHead.isEmpty else {
            return nil
        }
        return originHead.removingPrefix("origin/")
    }
}

public final class DefaultGitCommandRunner: GitCommandRunning, @unchecked Sendable {
    public init() {}

    public func runGit(repositoryURL: URL?, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/git")
        if let repositoryURL {
            process.arguments = ["-C", repositoryURL.path] + arguments
        } else {
            process.arguments = arguments
        }

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw RepositoryRegistrationError.gitCommandFailed
        }

        return String(data: output, encoding: .utf8) ?? ""
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func removingPrefix(_ prefix: String) -> String {
        guard hasPrefix(prefix) else {
            return self
        }
        return String(dropFirst(prefix.count))
    }
}
