import Foundation

public struct CodexThreadGitInfo: Equatable, Sendable {
    public let sha: String
    public let branch: String
    public let originURL: String

    public init(sha: String, branch: String, originURL: String) {
        self.sha = sha
        self.branch = branch
        self.originURL = originURL
    }
}

public struct CodexThreadStartRequest: Equatable, Sendable {
    public let cwd: URL
    public let threadCwd: URL
    public let gitInfo: CodexThreadGitInfo?
    public let model: String
    public let reasoningEffort: CursorReasoningEffort
    public let prompt: String
    public let displayName: String?

    public init(
        cwd: URL,
        threadCwd: URL? = nil,
        gitInfo: CodexThreadGitInfo? = nil,
        model: String,
        reasoningEffort: CursorReasoningEffort,
        prompt: String,
        displayName: String? = nil
    ) {
        self.cwd = cwd
        self.threadCwd = threadCwd ?? cwd
        self.gitInfo = gitInfo
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.prompt = prompt
        self.displayName = displayName
    }
}

public struct CodexThreadReference: Equatable, Sendable {
    public let id: String
    public let url: URL?

    public init(id: String, url: URL?) {
        self.id = id
        self.url = url
    }

    public static func deepLinkURL(threadID: String) -> URL? {
        URL(string: "codex://threads/\(threadID)")
    }
}

public protocol CodexTurnCompletionWatching: Sendable {
    func waitUntilCompleted() async
}

public actor CodexTurnCompletionSignal: CodexTurnCompletionWatching {
    private var isCompleted: Bool
    private var continuations: [CheckedContinuation<Void, Never>] = []

    public init(isCompleted: Bool = false) {
        self.isCompleted = isCompleted
    }

    public func waitUntilCompleted() async {
        if isCompleted {
            return
        }

        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    public func complete() {
        guard !isCompleted else {
            return
        }
        isCompleted = true
        let continuations = continuations
        self.continuations.removeAll()
        for continuation in continuations {
            continuation.resume()
        }
    }
}

public struct CodexStartedThread: Sendable {
    public let reference: CodexThreadReference
    public let turnCompletion: any CodexTurnCompletionWatching

    public init(reference: CodexThreadReference, turnCompletion: any CodexTurnCompletionWatching) {
        self.reference = reference
        self.turnCompletion = turnCompletion
    }
}

public protocol CodexAppServerClient: Sendable {
    func startThreadAndTurn(_ request: CodexThreadStartRequest) async throws -> CodexStartedThread
}

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

    public func startThreadAndTurn(_ request: CodexThreadStartRequest) async throws -> CodexStartedThread {
        await gate.wait()
        do {
            let startedThread = try await transport.startThreadAndTurn(request)
            await gate.signal()
            return startedThread
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
    private var pendingTurnCompletionsByThreadID: [String: CodexTurnCompletionSignal] = [:]

    init(executableURL: URL, arguments: [String]) {
        self.executableURL = executableURL
        self.arguments = arguments
    }

    deinit {
        process?.terminate()
    }

    func startThreadAndTurn(_ request: CodexThreadStartRequest) async throws -> CodexStartedThread {
        do {
            try await ensureInitialized()

            let threadResponse = try await sendRequest(
                method: "thread/start",
                params: [
                    "cwd": request.threadCwd.path,
                    "model": request.model,
                    "ephemeral": false
                ]
            )
            let thread = try threadReference(fromThreadStartResponse: threadResponse)

            try await updateThreadGitMetadataIfPresent(threadID: thread.id, gitInfo: request.gitInfo)
            try await setThreadNameIfPresent(threadID: thread.id, displayName: request.displayName)
            let turnCompletion = CodexTurnCompletionSignal()
            pendingTurnCompletionsByThreadID[thread.id] = turnCompletion
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
                            "text": request.prompt,
                            "text_elements": []
                        ]
                    ]
                ]
            )

            return CodexStartedThread(reference: thread, turnCompletion: turnCompletion)
        } catch {
            resetProcessState()
            throw error
        }
    }

    private func updateThreadGitMetadataIfPresent(threadID: String, gitInfo: CodexThreadGitInfo?) async throws {
        guard let gitInfo else {
            return
        }

        do {
            _ = try await sendRequest(
                method: "thread/metadata/update",
                params: [
                    "threadId": threadID,
                    "gitInfo": [
                        "sha": gitInfo.sha,
                        "branch": gitInfo.branch,
                        "originUrl": gitInfo.originURL
                    ]
                ]
            )
        } catch CodexAppServerClientError.serverRejected {
            return
        }
    }

    private func setThreadNameIfPresent(threadID: String, displayName: String?) async throws {
        guard let displayName = normalizedThreadName(displayName) else {
            return
        }

        do {
            _ = try await sendRequest(
                method: "thread/name/set",
                params: [
                    "threadId": threadID,
                    "name": displayName
                ]
            )
        } catch CodexAppServerClientError.serverRejected {
            return
        }
    }

    private func normalizedThreadName(_ displayName: String?) -> String? {
        guard let displayName else {
            return nil
        }
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            return nil
        }
        return name
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
        process.environment = CodexProcessEnvironment.augmentedEnvironment(binaryURL: executableURL)

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
            handleServerNotification(response)
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

    private func handleServerNotification(_ response: CodexAppServerRPCResponse) {
        guard let threadID = terminalTurnThreadID(from: response) else {
            return
        }
        guard let completion = pendingTurnCompletionsByThreadID.removeValue(forKey: threadID) else {
            return
        }
        Task {
            await completion.complete()
        }
    }

    private func terminalTurnThreadID(from response: CodexAppServerRPCResponse) -> String? {
        if response.method == "turn/completed" || response.method == "turn/aborted" {
            return response.params?.threadId
        }

        guard response.method == "codex/event", response.params?.isTerminalTurnEvent == true else {
            return nil
        }
        return response.params?.threadId
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
        let orphanedCompletions = Array(pendingTurnCompletionsByThreadID.values)
        pendingTurnCompletionsByThreadID.removeAll()
        for completion in orphanedCompletions {
            Task {
                await completion.complete()
            }
        }
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

        let url = CodexThreadReference.deepLinkURL(threadID: threadID)
        return CodexThreadReference(id: threadID, url: url)
    }
}

private struct CodexAppServerRPCResponse: Decodable, Sendable {
    let id: Int?
    let method: String?
    let params: CodexAppServerRPCParams?
    let result: CodexAppServerRPCResult?
    let error: CodexAppServerRPCError?
}

private struct CodexAppServerRPCParams: Decodable, Sendable {
    let threadId: String?
    let event: CodexAppServerRPCEvent?
    let msg: CodexAppServerRPCEvent?

    var isTerminalTurnEvent: Bool {
        let eventType = event?.type ?? msg?.type
        return eventType == "task_complete"
            || eventType == "turn_aborted"
            || eventType == "interrupted"
    }
}

private struct CodexAppServerRPCEvent: Decodable, Sendable {
    let type: String?
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
