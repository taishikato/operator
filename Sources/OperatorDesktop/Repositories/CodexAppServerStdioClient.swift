import Foundation

public final class CodexAppServerStdioClient: CodexAppServerClient, @unchecked Sendable {
    private let gate = AsyncGate()
    private let transport: CodexAppServerStdioTransport

    public init(
        executableURL: URL = URL(filePath: "/usr/bin/env"),
        arguments: [String] = ["codex", "app-server", "--listen", "stdio://"]
    ) {
        transport = CodexAppServerStdioTransport(executableURL: executableURL, arguments: arguments)
    }

    public convenience init(codexBinaryURL: URL) {
        self.init(executableURL: codexBinaryURL, arguments: ["app-server", "--listen", "stdio://"])
    }

    deinit {
        let transport = transport
        Task {
            await transport.close()
        }
    }

    public func startThreadAndTurn(_ request: CodexThreadStartRequest) async throws -> CodexThreadReference {
        await gate.wait()
        do {
            let thread = try await transport.startThreadAndTurn(request)
            await gate.signal()
            return thread
        } catch {
            await gate.signal()
            throw error
        }
    }
}

private actor CodexAppServerStdioTransport {
    private let executableURL: URL
    private let arguments: [String]
    private var process: Process?
    private var stdin: FileHandle?
    private var stdout: FileHandle?
    private var stderr: FileHandle?
    private var stdoutBuffer = Data()
    private var nextRequestID = 1
    private var initialized = false
    private var pendingResponses: [Int: CheckedContinuation<CodexAppServerRPCResponse, Error>] = [:]

    init(executableURL: URL, arguments: [String]) {
        self.executableURL = executableURL
        self.arguments = arguments
    }

    deinit {
        process?.terminate()
    }

    func startThreadAndTurn(_ request: CodexThreadStartRequest) async throws -> CodexThreadReference {
        do {
            try await ensureInitialized()

            let threadResponse = try await sendRequest(
                method: "thread/start",
                params: [
                    "cwd": request.cwd.path,
                    "model": request.model,
                    "ephemeral": false
                ]
            )
            let thread = try threadReference(fromThreadStartResponse: threadResponse)

            _ = try await sendRequest(
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
        } catch {
            resetProcessState()
            throw error
        }
    }

    func close() {
        resetProcessState()
    }

    private func ensureInitialized() async throws {
        try ensureProcessStarted()
        guard !initialized else {
            return
        }

        _ = try await sendRequest(
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
        let errorPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            throw CodexAppServerClientError.binaryNotFound(path: executableURL.path)
        }
        self.process = process
        stdin = inputPipe.fileHandleForWriting
        stdout = outputPipe.fileHandleForReading
        stderr = errorPipe.fileHandleForReading

        stdout?.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task {
                await self?.receiveStdoutData(data)
            }
        }
        stderr?.readabilityHandler = { handle in
            _ = handle.availableData
        }
    }

    private func sendRequest(method: String, params: [String: Any]) async throws -> CodexAppServerRPCResponse {
        guard let stdin else {
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
        var data = try JSONSerialization.data(withJSONObject: message)
        data.append(0x0A)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CodexAppServerRPCResponse, Error>) in
                pendingResponses[requestID] = continuation
                stdin.write(data)
            }
        } onCancel: {
            Task {
                await self.cancelRequest(id: requestID)
            }
        }
    }

    private func cancelRequest(id: Int) {
        pendingResponses.removeValue(forKey: id)?
            .resume(throwing: CodexAppServerClientError.connectionClosed)
    }

    private func receiveStdoutData(_ data: Data) {
        guard !data.isEmpty else {
            failPendingResponses(with: CodexAppServerClientError.connectionClosed)
            resetProcessState(terminate: false)
            return
        }

        stdoutBuffer.append(data)
        while let newlineIndex = stdoutBuffer.firstIndex(of: 0x0A) {
            let line = stdoutBuffer[..<newlineIndex]
            stdoutBuffer.removeSubrange(...newlineIndex)
            guard !line.isEmpty else {
                continue
            }
            handleStdoutLine(Data(line))
        }
    }

    private func handleStdoutLine(_ line: Data) {
        guard let response = try? JSONDecoder().decode(CodexAppServerRPCResponse.self, from: line) else {
            failPendingResponses(with: CodexAppServerClientError.invalidResponse)
            resetProcessState()
            return
        }

        if response.method != nil {
            return
        }
        guard let requestID = response.id else {
            return
        }
        guard let continuation = pendingResponses.removeValue(forKey: requestID) else {
            return
        }
        if let error = response.error {
            continuation.resume(
                throwing: CodexAppServerClientError.serverRejected(
                    message: error.message ?? "app-server rejected request"
                )
            )
            return
        }
        continuation.resume(returning: response)
    }

    private func resetProcessState(terminate: Bool = true) {
        stdout?.readabilityHandler = nil
        stderr?.readabilityHandler = nil
        if terminate {
            process?.terminate()
        }
        process = nil
        stdin = nil
        stdout = nil
        stderr = nil
        stdoutBuffer.removeAll()
        initialized = false
    }

    private func failPendingResponses(with error: Error) {
        let responses = pendingResponses.values
        pendingResponses.removeAll()
        for response in responses {
            response.resume(throwing: error)
        }
    }

    private func threadReference(fromThreadStartResponse response: CodexAppServerRPCResponse) throws -> CodexThreadReference {
        guard let threadID = response.result?.thread?.id else {
            throw CodexAppServerClientError.invalidResponse
        }

        let url = URL(string: "codex://thread/\(threadID)")
        return CodexThreadReference(id: threadID, url: url)
    }
}

private struct CodexAppServerRPCResponse: Decodable, Sendable {
    let id: Int?
    let method: String?
    let result: CodexAppServerRPCResult?
    let error: CodexAppServerRPCError?
}

private struct CodexAppServerRPCResult: Decodable, Sendable {
    let thread: CodexAppServerRPCThread?
}

private struct CodexAppServerRPCThread: Decodable, Sendable {
    let id: String
}

private struct CodexAppServerRPCError: Decodable, Sendable {
    let message: String?
}

private actor AsyncGate {
    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if !isLocked {
            isLocked = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func signal() {
        if waiters.isEmpty {
            isLocked = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}

public enum CodexAppServerClientError: Error, Equatable, LocalizedError, Sendable {
    case binaryNotFound(path: String)
    case notConnected
    case connectionClosed
    case invalidResponse
    case serverRejected(message: String)

    public var errorDescription: String? {
        switch self {
        case let .binaryNotFound(path):
            "Codex binary not found at \(path). Configure an absolute Codex binary path in Settings."
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
