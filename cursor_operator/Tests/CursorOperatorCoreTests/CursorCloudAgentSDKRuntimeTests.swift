import Foundation
import Testing
@testable import CursorOperatorCore

@Test func sdkRuntimeStartsCloudAgentThroughHelperJSON() async throws {
    let runner = FakeSDKHelperRunner(response: Data("""
        {"agentID":"agent-sdk","runID":"run-sdk","openURL":"https://cursor.com/agents/agent-sdk"}
        """.utf8))
    let runtime = CursorCloudAgentSDKRuntime(
        helperScriptURL: URL(filePath: "/tmp/cursor-sdk-helper.mjs"),
        runner: runner
    )

    let reference = try await runtime.startCloudAgent(
        request: CursorCloudAgentRequestPreview(
            agentName: "SDK send",
            prompt: "Prompt",
            repositoryURL: URL(string: "https://github.com/example/operator")!,
            startingRef: "main",
            model: CursorModel.fixed,
            autoCreatePR: false
        ),
        apiKey: "crsr_test_key"
    )

    #expect(reference == CursorCloudAgentReference(
        agentID: "agent-sdk",
        runID: "run-sdk",
        openURL: URL(string: "https://cursor.com/agents/agent-sdk")!
    ))
    #expect(runner.inputs.map(\.action) == [.start])
    #expect(runner.inputs.first?.agentName == "SDK send")
    #expect(runner.inputs.first?.repositoryURL == URL(string: "https://github.com/example/operator")!)
    #expect(runner.inputs.first?.apiKey == "crsr_test_key")
}

@Test func sdkRuntimeWaitsForCloudRunThroughHelperJSON() async throws {
    let runner = FakeSDKHelperRunner(response: Data("""
        {"status":"finished","result":"Complete"}
        """.utf8))
    let runtime = CursorCloudAgentSDKRuntime(
        helperScriptURL: URL(filePath: "/tmp/cursor-sdk-helper.mjs"),
        runner: runner
    )

    let completion = try await runtime.waitForRun(
        reference: CursorCloudAgentReference(
            agentID: "agent-sdk",
            runID: "run-sdk",
            openURL: URL(string: "https://cursor.com/agents/agent-sdk")!
        ),
        apiKey: "crsr_test_key"
    )

    #expect(completion == CursorCloudAgentRunCompletion(status: "finished", result: "Complete"))
    #expect(runner.inputs.map(\.action) == [.wait])
    #expect(runner.inputs.first?.agentID == "agent-sdk")
    #expect(runner.inputs.first?.runID == "run-sdk")
}

@Test func sdkRuntimeRejectsUnexpectedHelperResponses() async throws {
    let startRuntime = CursorCloudAgentSDKRuntime(
        helperScriptURL: URL(filePath: "/tmp/cursor-sdk-helper.mjs"),
        runner: FakeSDKHelperRunner(response: Data("""
            {"agentID":"agent-sdk","runID":"run-sdk","openURL":"http://[::1"}
            """.utf8))
    )
    await #expect(throws: CursorRuntimeFailure(message: "Cursor SDK helper returned an invalid agent URL.")) {
        _ = try await startRuntime.startCloudAgent(
            request: CursorCloudAgentRequestPreview(
                agentName: "SDK invalid URL",
                prompt: "Prompt",
                repositoryURL: URL(string: "https://github.com/example/operator")!,
                startingRef: "main",
                model: CursorModel.fixed,
                autoCreatePR: false
            ),
            apiKey: "crsr_test_key"
        )
    }

    let waitRuntime = CursorCloudAgentSDKRuntime(
        helperScriptURL: URL(filePath: "/tmp/cursor-sdk-helper.mjs"),
        runner: FakeSDKHelperRunner(response: Data("""
            {"result":"missing status"}
            """.utf8))
    )
    await #expect(throws: CursorRuntimeFailure(message: "Cursor SDK helper returned an unexpected wait response.")) {
        _ = try await waitRuntime.waitForRun(
            reference: CursorCloudAgentReference(
                agentID: "agent-sdk",
                runID: "run-sdk",
                openURL: URL(string: "https://cursor.com/agents/agent-sdk")!
            ),
            apiKey: "crsr_test_key"
        )
    }
}

@Test func cursorRuntimeFailureSanitizesSensitiveAndVerboseMessages() {
    #expect(CursorRuntimeFailure(message: "").message == "Cursor run failed.")
    #expect(CursorRuntimeFailure(message: "Cursor SDK stderr").message == "Cursor SDK stderr")
    #expect(CursorRuntimeFailure(message: "Authorization failed").message == "Cursor run failed. See Cursor for details.")
    #expect(CursorRuntimeFailure(message: "Bad token crsr_secret_123").message == "Cursor run failed. See Cursor for details.")
    #expect(CursorRuntimeFailure(message: String(repeating: "x", count: 200)).message.count == 160)
}

@Test func cursorRuntimeFailureRedactsCredentialsWithoutCursorPrefixOrJSONBody() {
    // Secrets can appear in upstream failure strings without a `crsr_` prefix or a
    // JSON `{` body, e.g. a raw header or query echo. These must still be redacted
    // before they are persisted on a run or shown in the UI.
    #expect(CursorRuntimeFailure(message: "Run failed: token=abc123def456").message == "Cursor run failed. See Cursor for details.")
    #expect(CursorRuntimeFailure(message: "Rejected with Bearer eyJhbGciOiJIUzI1NiJ9").message == "Cursor run failed. See Cursor for details.")
    #expect(CursorRuntimeFailure(message: "Set-Cookie: session=deadbeef").message == "Cursor run failed. See Cursor for details.")
    #expect(CursorRuntimeFailure(message: "api_key=sk-live-1234567890").message == "Cursor run failed. See Cursor for details.")
    #expect(CursorRuntimeFailure(message: "password=hunter2").message == "Cursor run failed. See Cursor for details.")
}

@Test func sdkHelperSanitizeErrorRedactsCursorAPIKeys() throws {
    guard let nodeURL = nodeExecutableURL() else {
        return
    }

    let helperDirectory = URL(filePath: FileManager.default.currentDirectoryPath)
        .appending(path: "Resources", directoryHint: .isDirectory)
        .appending(path: "CursorSDKHelper", directoryHint: .isDirectory)
    let process = Process()
    process.executableURL = nodeURL
    process.currentDirectoryURL = helperDirectory
    process.arguments = [
        "--input-type=module",
        "-e",
        """
        import { sanitizeError } from "./cursor-sdk-helper.mjs";
        process.stdout.write(sanitizeError(new Error("failed with crsr_secret_123")));
        """
    ]

    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr
    try process.run()
    process.waitUntilExit()

    let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
    let stderrOutput = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    #expect(process.terminationStatus == 0, Comment(rawValue: stderrOutput))
    #expect(output == "failed with crsr_[redacted]", Comment(rawValue: stderrOutput))
}

private final class FakeSDKHelperRunner: CursorSDKHelperRunning, @unchecked Sendable {
    let response: Data
    private(set) var inputs: [CursorSDKHelperRequest] = []

    init(response: Data) {
        self.response = response
    }

    func run(helperScriptURL: URL, request: CursorSDKHelperRequest) async throws -> Data {
        inputs.append(request)
        return response
    }
}

private func nodeExecutableURL() -> URL? {
    ProcessInfo.processInfo.environment["PATH"]?
        .split(separator: ":")
        .map(String.init)
        .map { URL(filePath: $0).appending(path: "node") }
        .first { FileManager.default.isExecutableFile(atPath: $0.path) }
}
