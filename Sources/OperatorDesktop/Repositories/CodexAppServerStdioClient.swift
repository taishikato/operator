import Foundation

public final class CodexAppServerStdioClient: CodexAppServerClient, @unchecked Sendable {
    private let executableURL: URL
    private let arguments: [String]
    private var process: Process?
    private var stdin: FileHandle?
    private var stdout: FileHandle?
    private var nextRequestID = 1
    private var initialized = false

    public init(
        executableURL: URL = URL(filePath: "/usr/bin/env"),
        arguments: [String] = ["codex", "app-server", "--listen", "stdio://"]
    ) {
        self.executableURL = executableURL
        self.arguments = arguments
    }

    deinit {
        process?.terminate()
    }

    public func startThreadAndTurn(_ request: CodexThreadStartRequest) async throws -> CodexThreadReference {
        try await withCheckedThrowingContinuation { continuation in
            do {
                let thread = try startThreadAndTurnSynchronously(request)
                continuation.resume(returning: thread)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func startThreadAndTurnSynchronously(_ request: CodexThreadStartRequest) throws -> CodexThreadReference {
        try ensureInitialized()

        let threadResponse = try sendRequest(
            method: "thread/start",
            params: [
                "cwd": request.cwd.path,
                "model": request.model,
                "ephemeral": false
            ]
        )
        let thread = try threadReference(fromThreadStartResponse: threadResponse)

        _ = try sendRequest(
            method: "turn/start",
            params: [
                "threadId": thread.id,
                "cwd": request.cwd.path,
                "model": request.model,
                "effort": request.reasoningEffort.rawValue,
                "input": [
                    [
                        "type": "text",
                        "text": request.prompt
                    ]
                ]
            ]
        )

        return thread
    }

    private func ensureInitialized() throws {
        try ensureProcessStarted()
        guard !initialized else {
            return
        }

        _ = try sendRequest(
            method: "initialize",
            params: [
                "clientInfo": [
                    "name": "operator-desktop",
                    "title": "Operator",
                    "version": "0"
                ],
                "capabilities": [
                    "experimentalApi": true
                ]
            ]
        )
        initialized = true
    }

    private func ensureProcessStarted() throws {
        guard process == nil else {
            return
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        try process.run()
        self.process = process
        stdin = inputPipe.fileHandleForWriting
        stdout = outputPipe.fileHandleForReading
    }

    private func sendRequest(method: String, params: [String: Any]) throws -> [String: Any] {
        guard let stdin, let stdout else {
            throw CodexAppServerClientError.notConnected
        }

        let requestID = nextRequestID
        nextRequestID += 1
        let message: [String: Any] = [
            "jsonrpc": "2.0",
            "id": requestID,
            "method": method,
            "params": params
        ]
        let data = try JSONSerialization.data(withJSONObject: message)
        stdin.write(data)
        stdin.write(Data([0x0A]))

        while true {
            guard let line = try stdout.readLineData() else {
                throw CodexAppServerClientError.connectionClosed
            }
            let object = try JSONSerialization.jsonObject(with: line)
            guard let response = object as? [String: Any] else {
                continue
            }
            if response["method"] != nil {
                continue
            }
            guard response["id"] as? Int == requestID else {
                continue
            }
            if let error = response["error"] as? [String: Any] {
                throw CodexAppServerClientError.serverRejected(message: error["message"] as? String ?? "app-server rejected request")
            }
            return response
        }
    }

    private func threadReference(fromThreadStartResponse response: [String: Any]) throws -> CodexThreadReference {
        guard
            let result = response["result"] as? [String: Any],
            let thread = result["thread"] as? [String: Any],
            let threadID = thread["id"] as? String
        else {
            throw CodexAppServerClientError.invalidResponse
        }

        let url = URL(string: "codex://thread/\(threadID)")
        return CodexThreadReference(id: threadID, url: url)
    }
}

public enum CodexAppServerClientError: Error, Equatable, LocalizedError, Sendable {
    case notConnected
    case connectionClosed
    case invalidResponse
    case serverRejected(message: String)

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            "Unable to connect to codex app-server."
        case .connectionClosed:
            "codex app-server closed the connection."
        case .invalidResponse:
            "codex app-server returned an invalid response."
        case let .serverRejected(message):
            message
        }
    }
}

private extension FileHandle {
    func readLineData() throws -> Data? {
        var data = Data()
        while true {
            let byte = try read(upToCount: 1)
            guard let byte, !byte.isEmpty else {
                return data.isEmpty ? nil : data
            }
            if byte == Data([0x0A]) {
                return data
            }
            data.append(byte)
        }
    }
}
