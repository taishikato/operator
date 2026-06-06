import Foundation

public enum CodexOpenTarget: Equatable, Sendable {
    case url(URL)
    case worktree(URL)

    public init?(run: OperatorRun) {
        guard run.status == .triggered else {
            return nil
        }

        if let codexThreadURL = run.codexThreadURL {
            self = .url(codexThreadURL)
        } else {
            self = .worktree(URL(filePath: run.worktreePath, directoryHint: .isDirectory))
        }
    }
}

public struct CodexOpenCommand: Equatable, Sendable {
    public let executableURL: URL
    public let arguments: [String]

    public init(target: CodexOpenTarget) {
        executableURL = URL(filePath: "/usr/bin/open")
        switch target {
        case .url(let url):
            arguments = [url.absoluteString]
        case .worktree(let url):
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

public typealias NSWorkspaceCodexAppOpener = OSCodexAppOpener
