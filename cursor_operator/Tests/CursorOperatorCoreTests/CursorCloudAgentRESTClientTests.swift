import Foundation
import Testing
@testable import CursorOperatorCore

@Test func restClientCreatesOfficialAgentRequestAndDecodesReference() async throws {
    let transport = FakeCursorHTTPTransport(response: CursorHTTPResponse(
        statusCode: 201,
        data: Data("""
        {
          "agent": {
            "id": "agent-123",
            "url": "https://cursor.com/agents/agent-123"
          },
          "run": {
            "id": "run-123",
            "agentId": "agent-123",
            "status": "CREATING"
          }
        }
        """.utf8)
    ))
    let client = CursorCloudAgentRESTClient(
        baseURL: URL(string: "https://api.cursor.test")!,
        transport: transport
    )
    let preview = CursorCloudAgentRequestPreview(
        agentName: "REST send",
        prompt: "Prompt exactly",
        repositoryURL: URL(string: "https://github.com/example/operator")!,
        startingRef: "main",
        model: CursorModel.fixed,
        autoCreatePR: true
    )

    let reference = try await client.startCloudAgent(request: preview, apiKey: "crsr_test_key")

    #expect(reference.agentID == "agent-123")
    #expect(reference.runID == "run-123")
    #expect(reference.openURL == URL(string: "https://cursor.com/agents/agent-123")!)
    #expect(transport.requests.count == 1)
    let request = try #require(transport.requests.first)
    #expect(request.url == URL(string: "https://api.cursor.test/v1/agents")!)
    #expect(request.httpMethod == "POST")
    #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Basic Y3Jzcl90ZXN0X2tleTo=")

    let body = try #require(request.httpBody)
    let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    let prompt = try #require(json["prompt"] as? [String: Any])
    let model = try #require(json["model"] as? [String: Any])
    let repos = try #require(json["repos"] as? [[String: Any]])
    let repo = try #require(repos.first)
    #expect(prompt["text"] as? String == "Prompt exactly")
    #expect(model["id"] as? String == CursorModel.fixed)
    #expect(repo["url"] as? String == "https://github.com/example/operator")
    #expect(repo["startingRef"] as? String == "main")
    #expect(json["autoCreatePR"] as? Bool == true)
}

@Test func restClientMapsFailuresToSanitizedRuntimeFailures() async throws {
    let authClient = CursorCloudAgentRESTClient(
        baseURL: URL(string: "https://api.cursor.test")!,
        transport: FakeCursorHTTPTransport(response: CursorHTTPResponse(
            statusCode: 401,
            data: Data("{\"secret\":\"crsr_secret\"}".utf8)
        ))
    )
    let validationClient = CursorCloudAgentRESTClient(
        baseURL: URL(string: "https://api.cursor.test")!,
        transport: FakeCursorHTTPTransport(response: CursorHTTPResponse(
            statusCode: 422,
            data: Data("{\"repository\":\"invalid\"}".utf8)
        ))
    )
    let malformedClient = CursorCloudAgentRESTClient(
        baseURL: URL(string: "https://api.cursor.test")!,
        transport: FakeCursorHTTPTransport(response: CursorHTTPResponse(
            statusCode: 200,
            data: Data("not json".utf8)
        ))
    )
    let networkClient = CursorCloudAgentRESTClient(
        baseURL: URL(string: "https://api.cursor.test")!,
        transport: FakeCursorHTTPTransport(error: URLError(.notConnectedToInternet))
    )
    let preview = CursorCloudAgentRequestPreview(
        agentName: "REST failure",
        prompt: "Prompt",
        repositoryURL: URL(string: "https://github.com/example/operator")!,
        startingRef: "main",
        model: CursorModel.fixed,
        autoCreatePR: false
    )

    await #expect(throws: CursorRuntimeFailure(message: "Cursor API authentication failed.")) {
        try await authClient.startCloudAgent(request: preview, apiKey: "crsr_test_key")
    }
    await #expect(throws: CursorRuntimeFailure(message: "Cursor rejected the run request.")) {
        try await validationClient.startCloudAgent(request: preview, apiKey: "crsr_test_key")
    }
    await #expect(throws: CursorRuntimeFailure(message: "Cursor returned an unexpected response.")) {
        try await malformedClient.startCloudAgent(request: preview, apiKey: "crsr_test_key")
    }
    await #expect(throws: CursorRuntimeFailure(message: "Unable to reach Cursor Cloud Agent.")) {
        try await networkClient.startCloudAgent(request: preview, apiKey: "crsr_test_key")
    }
}

@Test func restClientRunsBehindSendServiceAndStoresCursorReference() async throws {
    let store = try CursorOperatorStore(databaseURL: temporaryRESTClientDatabaseURL())
    let repository = try store.createRepository(
        name: "operator",
        localPath: "/tmp/operator",
        githubURL: URL(string: "https://github.com/example/operator")!,
        defaultBranch: "main"
    )
    let task = try store.createTask(
        repositoryID: repository.id,
        title: "Send real REST",
        prompt: "Prompt exactly",
        autoCreatePR: true
    )
    let transport = FakeCursorHTTPTransport(response: CursorHTTPResponse(
        statusCode: 201,
        data: Data("""
        {
          "agent": {
            "id": "agent-service",
            "url": "https://cursor.com/agents/agent-service"
          },
          "run": {
            "id": "run-service",
            "agentId": "agent-service",
            "status": "CREATING"
          }
        }
        """.utf8)
    ))
    let service = CursorTaskSendService(
        store: store,
        credentialReadiness: CursorSendReadiness(provider: CursorCredentialProvider(
            store: InMemoryCursorCredentialStore(apiKey: "crsr_test_key"),
            environment: [:]
        )),
        runtime: CursorCloudAgentRESTClient(
            baseURL: URL(string: "https://api.cursor.test")!,
            transport: transport
        )
    )

    let attempt = try await service.send(taskID: task.id)

    #expect(attempt.status == .succeeded)
    #expect(attempt.cursorAgentID == "agent-service")
    #expect(attempt.cursorRunID == "run-service")
    #expect(attempt.cursorURL == URL(string: "https://cursor.com/agents/agent-service")!)
    #expect(try store.task(id: task.id)?.status == .running)
}

private final class FakeCursorHTTPTransport: CursorHTTPTransport, @unchecked Sendable {
    private let response: CursorHTTPResponse?
    private let error: Error?
    private(set) var requests: [URLRequest] = []

    init(response: CursorHTTPResponse) {
        self.response = response
        error = nil
    }

    init(error: Error) {
        response = nil
        self.error = error
    }

    func data(for request: URLRequest) async throws -> CursorHTTPResponse {
        requests.append(request)
        if let error {
            throw error
        }
        return try #require(response)
    }
}

private func temporaryRESTClientDatabaseURL() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "CursorCloudAgentRESTClientTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appending(path: "operator.sqlite")
}
