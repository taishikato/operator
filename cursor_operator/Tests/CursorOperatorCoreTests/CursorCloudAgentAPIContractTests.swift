import Foundation
import Testing
@testable import CursorOperatorCore

@Test func cloudAgentContractBuildsOfficialCreateAgentRequestShape() throws {
    let preview = CursorCloudAgentRequestPreview(
        agentName: "README setup",
        prompt: "Add a README with setup instructions",
        repositoryURL: URL(string: "https://github.com/your-org/your-repo")!,
        startingRef: "main",
        model: "composer-2.5",
        autoCreatePR: true
    )

    let request = try CursorCloudAgentAPIContract.createAgentRequest(preview: preview)

    #expect(request.method == "POST")
    #expect(request.path == "/v1/agents")
    #expect(request.auth == .basicAPIKeyWithEmptyPassword)
    #expect(request.bodyValue("prompt.text") as? String == preview.prompt)
    #expect(request.bodyValue("model.id") as? String == "composer-2.5")
    #expect(request.bodyValue("repos.0.url") as? String == preview.repositoryURL.absoluteString)
    #expect(request.bodyValue("repos.0.startingRef") as? String == "main")
    #expect(request.bodyValue("autoCreatePR") as? Bool == true)
}

@Test func cloudAgentContractMapsSuccessResponseToCursorReference() throws {
    let data = Data("""
    {
      "agent": {
        "id": "bc-00000000-0000-0000-0000-000000000001",
        "url": "https://cursor.com/agents/bc-00000000-0000-0000-0000-000000000001",
        "latestRunId": "run-00000000-0000-0000-0000-000000000001"
      },
      "run": {
        "id": "run-00000000-0000-0000-0000-000000000001",
        "agentId": "bc-00000000-0000-0000-0000-000000000001",
        "status": "CREATING"
      }
    }
    """.utf8)

    let reference = try CursorCloudAgentAPIContract.decodeCreateAgentResponse(data)

    #expect(reference.agentID == "bc-00000000-0000-0000-0000-000000000001")
    #expect(reference.runID == "run-00000000-0000-0000-0000-000000000001")
    #expect(reference.openURL == URL(string: "https://cursor.com/agents/bc-00000000-0000-0000-0000-000000000001")!)
}

@Test func cloudAgentContractSanitizesErrorResponses() {
    let auth = CursorCloudAgentAPIContract.sanitizedFailure(statusCode: 401, body: Data("secret api key leaked".utf8))
    let validation = CursorCloudAgentAPIContract.sanitizedFailure(statusCode: 422, body: Data("{\"error\":\"repository invalid\"}".utf8))
    let malformed = CursorCloudAgentAPIContract.sanitizedFailure(statusCode: 200, body: Data("not json".utf8))
    let network = CursorCloudAgentAPIContract.sanitizedNetworkFailure(URLError(.notConnectedToInternet))

    #expect(auth == "Cursor API authentication failed.")
    #expect(validation == "Cursor rejected the run request.")
    #expect(malformed == "Cursor returned an unexpected response.")
    #expect(network == "Unable to reach Cursor Cloud Agent.")
}

@Test func cloudAgentContractExcludesMVPOutOfScopeOwnershipFields() throws {
    let preview = CursorCloudAgentRequestPreview(
        agentName: "Exact prompt task",
        prompt: "Exact prompt",
        repositoryURL: URL(string: "https://github.com/example/operator")!,
        startingRef: "main",
        model: CursorModel.fixed,
        autoCreatePR: true
    )

    let request = try CursorCloudAgentAPIContract.createAgentRequest(preview: preview)
    let disallowedFields = [
        "branchName",
        "pullRequestTitle",
        "pullRequestBody",
        "rawLogs",
        "eventStream",
        "transcript",
        "diff",
        "commits",
        "testResults",
        "resultClassification",
        "webhookURL",
        "desktopDeepLink"
    ]

    for field in disallowedFields {
        #expect(request.bodyValue(field) == nil)
    }
    #expect(request.bodyValue("prompt.text") as? String == "Exact prompt")
}
