import Foundation

public enum CursorSDKHelperAction: String, Codable, Equatable, Sendable {
    case start
    case wait
}

public struct CursorSDKHelperRequest: Codable, Equatable, Sendable {
    public let action: CursorSDKHelperAction
    public let apiKey: String
    public let prompt: String?
    public let repositoryURL: URL?
    public let startingRef: String?
    public let model: String?
    public let autoCreatePR: Bool?
    public let agentID: String?
    public let runID: String?

    public init(
        action: CursorSDKHelperAction,
        apiKey: String,
        prompt: String? = nil,
        repositoryURL: URL? = nil,
        startingRef: String? = nil,
        model: String? = nil,
        autoCreatePR: Bool? = nil,
        agentID: String? = nil,
        runID: String? = nil
    ) {
        self.action = action
        self.apiKey = apiKey
        self.prompt = prompt
        self.repositoryURL = repositoryURL
        self.startingRef = startingRef
        self.model = model
        self.autoCreatePR = autoCreatePR
        self.agentID = agentID
        self.runID = runID
    }
}

public protocol CursorSDKHelperRunning: Sendable {
    func run(helperScriptURL: URL, request: CursorSDKHelperRequest) async throws -> Data
}

public struct CursorCloudAgentSDKRuntime: CursorCloudAgentRuntime {
    private let helperScriptURL: URL
    private let runner: any CursorSDKHelperRunning
    private let decoder = JSONDecoder()

    public init(
        helperScriptURL: URL = CursorCloudAgentSDKRuntime.defaultHelperScriptURL(),
        runner: any CursorSDKHelperRunning = ProcessCursorSDKHelperRunner()
    ) {
        self.helperScriptURL = helperScriptURL
        self.runner = runner
    }

    public func startCloudAgent(
        request: CursorCloudAgentRequestPreview,
        apiKey: String
    ) async throws -> CursorCloudAgentReference {
        let data = try await runner.run(
            helperScriptURL: helperScriptURL,
            request: CursorSDKHelperRequest(
                action: .start,
                apiKey: apiKey,
                prompt: request.prompt,
                repositoryURL: request.repositoryURL,
                startingRef: request.startingRef,
                model: request.model,
                autoCreatePR: request.autoCreatePR
            )
        )

        do {
            let response = try decoder.decode(StartResponse.self, from: data)
            guard let openURL = URL(string: response.openURL) else {
                throw CursorRuntimeFailure(message: "Cursor SDK helper returned an invalid agent URL.")
            }
            return CursorCloudAgentReference(
                agentID: response.agentID,
                runID: response.runID,
                openURL: openURL
            )
        } catch let failure as CursorRuntimeFailure {
            throw failure
        } catch {
            throw CursorRuntimeFailure(message: "Cursor SDK helper returned an unexpected start response.")
        }
    }

    public func waitForRun(
        reference: CursorCloudAgentReference,
        apiKey: String
    ) async throws -> CursorCloudAgentRunCompletion {
        let data = try await runner.run(
            helperScriptURL: helperScriptURL,
            request: CursorSDKHelperRequest(
                action: .wait,
                apiKey: apiKey,
                agentID: reference.agentID,
                runID: reference.runID
            )
        )

        do {
            let response = try decoder.decode(WaitResponse.self, from: data)
            return CursorCloudAgentRunCompletion(
                status: response.status,
                result: response.result
            )
        } catch {
            throw CursorRuntimeFailure(message: "Cursor SDK helper returned an unexpected wait response.")
        }
    }

    public static func defaultHelperScriptURL() -> URL {
        if let resourceURL = Bundle.main.resourceURL {
            return resourceURL
                .appending(path: "CursorSDKHelper", directoryHint: .isDirectory)
                .appending(path: "cursor-sdk-helper.mjs")
        }

        return URL(filePath: "Resources/CursorSDKHelper/cursor-sdk-helper.mjs")
    }
}

public struct ProcessCursorSDKHelperRunner: CursorSDKHelperRunning {
    public init() {}

    public func run(helperScriptURL: URL, request: CursorSDKHelperRequest) async throws -> Data {
        try await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(filePath: "/usr/bin/env")
            process.arguments = ["node", helperScriptURL.path]

            let stdin = Pipe()
            let stdout = Pipe()
            let stderr = Pipe()
            process.standardInput = stdin
            process.standardOutput = stdout
            process.standardError = stderr

            do {
                try process.run()
                try stdin.fileHandleForWriting.write(contentsOf: JSONEncoder().encode(request))
                try stdin.fileHandleForWriting.close()
                process.waitUntilExit()
            } catch {
                throw CursorRuntimeFailure(message: "Unable to launch Cursor SDK helper.")
            }

            let output = stdout.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = stderr.fileHandleForReading.readDataToEndOfFile()

            guard process.terminationStatus == 0 else {
                let message = String(data: errorOutput, encoding: .utf8) ?? "Cursor SDK helper failed."
                throw CursorRuntimeFailure(message: message)
            }

            return output
        }.value
    }
}

private struct StartResponse: Decodable {
    let agentID: String
    let runID: String
    let openURL: String
}

private struct WaitResponse: Decodable {
    let status: String
    let result: String?
}
