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
