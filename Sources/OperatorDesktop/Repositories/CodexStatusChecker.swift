import Foundation

public enum CodexStatus: Equatable, Sendable {
    case notChecked
    case ready(URL)
    case notFound
    case notAuthenticatedOrUnavailable(String)

    public var title: String {
        switch self {
        case .notChecked:
            "Not checked"
        case .ready:
            "Ready"
        case .notFound:
            "Not found"
        case .notAuthenticatedOrUnavailable:
            "Not authenticated or unavailable"
        }
    }

    public var message: String {
        switch self {
        case .notChecked:
            "Codex status has not been checked yet."
        case let .ready(binaryURL):
            "Codex is available at \(binaryURL.path)."
        case .notFound:
            "Codex binary was not found. Install Codex CLI/App or set an absolute binary path."
        case let .notAuthenticatedOrUnavailable(message):
            message
        }
    }
}

public enum CodexStatusRunnerSuccess: Equatable, Sendable {
    case ready
}

public enum CodexStatusRunnerFailure: Error, Equatable, Sendable {
    case notAuthenticatedOrUnavailable(String)
}

public protocol CodexStatusRunning: Sendable {
    func runCodexStatus(binaryURL: URL) async -> Result<CodexStatusRunnerSuccess, CodexStatusRunnerFailure>
}

public protocol CodexStatusChecking: Sendable {
    func checkStatus(binaryURL: URL?) async -> CodexStatus
}

public struct CodexStatusChecker: CodexStatusChecking {
    private let runner: any CodexStatusRunning

    public init(runner: any CodexStatusRunning = ProcessCodexStatusRunner()) {
        self.runner = runner
    }

    public func checkStatus(binaryURL: URL?) async -> CodexStatus {
        guard let binaryURL else {
            return .notFound
        }

        switch await runner.runCodexStatus(binaryURL: binaryURL) {
        case .success:
            return .ready(binaryURL)
        case let .failure(.notAuthenticatedOrUnavailable(message)):
            return .notAuthenticatedOrUnavailable(message)
        }
    }
}

public struct ProcessCodexStatusRunner: CodexStatusRunning {
    public init() {}

    public func runCodexStatus(binaryURL: URL) async -> Result<CodexStatusRunnerSuccess, CodexStatusRunnerFailure> {
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = binaryURL
            process.arguments = ["login", "status"]
            process.environment = CodexProcessEnvironment.augmentedEnvironment(binaryURL: binaryURL)

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                return .failure(.notAuthenticatedOrUnavailable(
                    "Unable to run Codex at \(binaryURL.path). Check the binary path in Settings."
                ))
            }

            if process.terminationStatus == 0 {
                return .success(.ready)
            }

            let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = [
                String(data: output, encoding: .utf8),
                String(data: errorOutput, encoding: .utf8)
            ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

            if message.isEmpty {
                return .failure(.notAuthenticatedOrUnavailable(
                    "Codex is not authenticated or unavailable. Open Codex CLI or App and sign in."
                ))
            }
            return .failure(.notAuthenticatedOrUnavailable(message))
        }.value
    }
}
