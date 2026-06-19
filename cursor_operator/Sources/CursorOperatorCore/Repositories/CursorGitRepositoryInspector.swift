import Foundation

public struct CursorRepositoryInspection: Equatable, Sendable {
    public let name: String
    public let localPath: String
    public let githubURL: URL
    public let defaultBranch: String

    public init(name: String, localPath: String, githubURL: URL, defaultBranch: String) {
        self.name = name
        self.localPath = localPath
        self.githubURL = githubURL
        self.defaultBranch = defaultBranch
    }
}

public enum CursorRepositoryRegistrationError: Error, Equatable, LocalizedError, Sendable {
    case invalidGitRepository(path: String)
    case missingGitHubOrigin
    case unsupportedRemoteURL(String)
    case gitCommandFailed

    public var errorDescription: String? {
        switch self {
        case .invalidGitRepository:
            "Selected folder is not a Git repository."
        case .missingGitHubOrigin:
            "Selected repository must have a GitHub origin remote."
        case .unsupportedRemoteURL:
            "Origin remote must be a GitHub repository URL."
        case .gitCommandFailed:
            "Unable to inspect the selected Git repository."
        }
    }
}

public protocol CursorRepositoryInspecting: Sendable {
    func inspect(_ repositoryURL: URL) throws -> CursorRepositoryInspection
}

public protocol CursorGitCommandRunning: AnyObject, Sendable {
    func runGit(repositoryURL: URL?, arguments: [String]) throws -> String
}

public struct CursorGitRepositoryInspector: CursorRepositoryInspecting, Sendable {
    private let commandRunner: any CursorGitCommandRunning

    public init(commandRunner: any CursorGitCommandRunning = DefaultCursorGitCommandRunner()) {
        self.commandRunner = commandRunner
    }

    public func inspect(_ repositoryURL: URL) throws -> CursorRepositoryInspection {
        let rootPath: String
        do {
            rootPath = try commandRunner
                .runGit(repositoryURL: repositoryURL, arguments: ["rev-parse", "--show-toplevel"])
                .trimmed
        } catch {
            throw CursorRepositoryRegistrationError.invalidGitRepository(path: repositoryURL.path)
        }

        guard !rootPath.isEmpty else {
            throw CursorRepositoryRegistrationError.invalidGitRepository(path: repositoryURL.path)
        }

        let rootURL = URL(filePath: rootPath).standardizedFileURL
        let originURL = try originRemoteURL(repositoryURL: rootURL)
        let githubURL = try Self.normalizedGitHubURL(from: originURL)

        return CursorRepositoryInspection(
            name: rootURL.lastPathComponent,
            localPath: rootURL.path,
            githubURL: githubURL,
            defaultBranch: try inferDefaultBranch(repositoryURL: rootURL)
        )
    }

    private func originRemoteURL(repositoryURL: URL) throws -> String {
        let origin: String
        do {
            origin = try commandRunner
                .runGit(repositoryURL: repositoryURL, arguments: ["config", "--get", "remote.origin.url"])
                .trimmed
        } catch {
            throw CursorRepositoryRegistrationError.missingGitHubOrigin
        }
        guard !origin.isEmpty else {
            throw CursorRepositoryRegistrationError.missingGitHubOrigin
        }
        return origin
    }

    private func inferDefaultBranch(repositoryURL: URL) throws -> String {
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
        return currentBranch.isEmpty ? "main" : currentBranch
    }

    private func branchName(fromOriginHead originHead: String) -> String? {
        guard !originHead.isEmpty else {
            return nil
        }
        return originHead.removingPrefix("origin/")
    }

    public static func normalizedGitHubURL(from remoteURL: String) throws -> URL {
        let trimmed = remoteURL.trimmed
        let ownerAndName: String

        if trimmed.hasPrefix("git@github.com:") {
            ownerAndName = String(trimmed.dropFirst("git@github.com:".count))
        } else if trimmed.hasPrefix("ssh://git@github.com/") {
            ownerAndName = String(trimmed.dropFirst("ssh://git@github.com/".count))
        } else if let url = URL(string: trimmed),
                  url.scheme == "https",
                  url.host == "github.com" {
            ownerAndName = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        } else {
            throw CursorRepositoryRegistrationError.unsupportedRemoteURL(trimmed)
        }

        let normalizedPath = ownerAndName.removingSuffix(".git")
        guard normalizedPath.split(separator: "/").count >= 2,
              let normalizedURL = URL(string: "https://github.com/\(normalizedPath)") else {
            throw CursorRepositoryRegistrationError.unsupportedRemoteURL(trimmed)
        }
        return normalizedURL
    }
}

public final class DefaultCursorGitCommandRunner: CursorGitCommandRunning, @unchecked Sendable {
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
            throw CursorRepositoryRegistrationError.gitCommandFailed
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

    func removingSuffix(_ suffix: String) -> String {
        guard hasSuffix(suffix) else {
            return self
        }
        return String(dropLast(suffix.count))
    }
}
