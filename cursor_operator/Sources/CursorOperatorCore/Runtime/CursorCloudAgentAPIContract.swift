import Foundation

public struct CursorCloudAgentRequestPreview: Equatable, Sendable {
    public let agentName: String
    public let prompt: String
    public let repositoryURL: URL
    public let startingRef: String
    public let model: String
    public let autoCreatePR: Bool

    public init(
        agentName: String,
        prompt: String,
        repositoryURL: URL,
        startingRef: String,
        model: String,
        autoCreatePR: Bool
    ) {
        self.agentName = agentName
        self.prompt = prompt
        self.repositoryURL = repositoryURL
        self.startingRef = startingRef
        self.model = model
        self.autoCreatePR = autoCreatePR
    }
}

public enum CursorCloudAgentAuth: Equatable, Sendable {
    case basicAPIKeyWithEmptyPassword
}

public struct CursorCloudAgentRequestContract: Equatable, Sendable {
    public let method: String
    public let path: String
    public let auth: CursorCloudAgentAuth
    public let body: [String: AnySendable]

    public func bodyValue(_ path: String) -> Any? {
        var current: Any = body
        for component in path.split(separator: ".").map(String.init) {
            if let dictionary = current as? [String: AnySendable] {
                guard let next = dictionary[component] else { return nil }
                current = next.value
            } else if let array = current as? [AnySendable],
                      let index = Int(component),
                      array.indices.contains(index) {
                current = array[index].value
            } else {
                return nil
            }
        }
        return current
    }
}

public struct AnySendable: @unchecked Sendable, Equatable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public static func == (lhs: AnySendable, rhs: AnySendable) -> Bool {
        String(describing: lhs.value) == String(describing: rhs.value)
    }
}

public struct CursorCloudAgentReference: Equatable, Sendable {
    public let agentID: String
    public let runID: String
    public let openURL: URL
}

public enum CursorCloudAgentAPIContract {
    public static let baseURL = URL(string: "https://api.cursor.com")!
    public static let createAgentPath = "/v1/agents"

    public static func createAgentRequest(preview: CursorCloudAgentRequestPreview) throws -> CursorCloudAgentRequestContract {
        CursorCloudAgentRequestContract(
            method: "POST",
            path: createAgentPath,
            auth: .basicAPIKeyWithEmptyPassword,
            body: [
                "prompt": AnySendable(["text": AnySendable(preview.prompt)] as [String: AnySendable]),
                "model": AnySendable(["id": AnySendable(preview.model)] as [String: AnySendable]),
                "repos": AnySendable([
                    AnySendable([
                        "url": AnySendable(preview.repositoryURL.absoluteString),
                        "startingRef": AnySendable(preview.startingRef)
                    ] as [String: AnySendable])
                ]),
                "autoCreatePR": AnySendable(preview.autoCreatePR)
            ]
        )
    }

    public static func jsonBodyData(for contract: CursorCloudAgentRequestContract) throws -> Data {
        try JSONSerialization.data(withJSONObject: jsonObject(contract.body), options: [.sortedKeys])
    }

    public static func decodeCreateAgentResponse(_ data: Data) throws -> CursorCloudAgentReference {
        let response = try JSONDecoder().decode(CreateAgentResponse.self, from: data)
        guard let openURL = URL(string: response.agent.url) else {
            throw CursorCloudAgentContractError.malformedResponse
        }
        return CursorCloudAgentReference(
            agentID: response.agent.id,
            runID: response.run.id,
            openURL: openURL
        )
    }

    public static func sanitizedFailure(statusCode: Int, body: Data) -> String {
        switch statusCode {
        case 401, 403:
            "Cursor API authentication failed."
        case 400, 404, 409, 422:
            "Cursor rejected the run request."
        default:
            "Cursor returned an unexpected response."
        }
    }

    public static func sanitizedNetworkFailure(_ error: Error) -> String {
        "Unable to reach Cursor Cloud Agent."
    }

    private static func jsonObject(_ value: AnySendable) -> Any {
        jsonObject(value.value)
    }

    private static func jsonObject(_ value: Any) -> Any {
        if let dictionary = value as? [String: AnySendable] {
            return dictionary.mapValues(jsonObject)
        }
        if let array = value as? [AnySendable] {
            return array.map(jsonObject)
        }
        return value
    }
}

public enum CursorCloudAgentContractError: Error, Equatable, Sendable {
    case malformedResponse
}

private struct CreateAgentResponse: Decodable {
    let agent: Agent
    let run: Run

    struct Agent: Decodable {
        let id: String
        let url: String
    }

    struct Run: Decodable {
        let id: String
    }
}
