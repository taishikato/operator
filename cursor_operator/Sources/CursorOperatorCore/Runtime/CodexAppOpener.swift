import Foundation

public enum CodexOpenTarget: Equatable, Sendable {
    case url(URL)
    case worktree(URL)

    public init?(run: OperatorRun) {
        guard run.harness == .codex, run.status != .failed else {
            return nil
        }

        if let codexThreadID = run.codexThreadID,
           let codexThreadURL = CodexThreadReference.deepLinkURL(threadID: codexThreadID) {
            self = .url(codexThreadURL)
        } else if let codexThreadURL = run.codexThreadURL {
            self = .url(codexThreadURL)
        } else if let worktreePath = run.worktreePath {
            self = .worktree(URL(filePath: worktreePath, directoryHint: .isDirectory))
        } else {
            self = .worktree(run.repositoryURL)
        }
    }
}

public struct CodexOpenCommand: Equatable, Sendable {
    public let executableURL: URL
    public let arguments: [String]

    public init(target: CodexOpenTarget) {
        executableURL = URL(filePath: "/usr/bin/open")
        switch target {
        case let .url(url):
            arguments = [url.absoluteString]
        case let .worktree(url):
            arguments = ["-a", "Codex", url.path]
        }
    }
}

public protocol CodexAppOpening: Sendable {
    func open(_ target: CodexOpenTarget) throws
}

public enum CodexAppOpenError: Error, Equatable, LocalizedError, Sendable {
    case openFailed

    public var errorDescription: String? {
        switch self {
        case .openFailed:
            "Unable to open Codex App."
        }
    }
}

public struct OSCodexAppOpener: CodexAppOpening {
    public init() {}

    public func open(_ target: CodexOpenTarget) throws {
        let command = CodexOpenCommand(target: target)
        let process = Process()
        process.executableURL = command.executableURL
        process.arguments = command.arguments

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw CodexAppOpenError.openFailed
        }

        guard process.terminationStatus == 0 else {
            throw CodexAppOpenError.openFailed
        }
    }
}
