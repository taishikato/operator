import Foundation

public struct CursorHTTPResponse: Equatable, Sendable {
    public let statusCode: Int
    public let data: Data

    public init(statusCode: Int, data: Data) {
        self.statusCode = statusCode
        self.data = data
    }
}

public protocol CursorHTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> CursorHTTPResponse
}

public struct URLSessionCursorHTTPTransport: CursorHTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> CursorHTTPResponse {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CursorRuntimeFailure(message: CursorCloudAgentAPIContract.sanitizedNetworkFailure(URLError(.badServerResponse)))
        }
        return CursorHTTPResponse(statusCode: httpResponse.statusCode, data: data)
    }
}

public struct CursorCloudAgentRESTClient: CursorCloudAgentRuntime {
    private let baseURL: URL
    private let transport: any CursorHTTPTransport

    public init(
        baseURL: URL = CursorCloudAgentAPIContract.baseURL,
        transport: any CursorHTTPTransport = URLSessionCursorHTTPTransport()
    ) {
        self.baseURL = baseURL
        self.transport = transport
    }

    public func startCloudAgent(request preview: CursorCloudAgentRequestPreview, apiKey: String) async throws -> CursorCloudAgentReference {
        let contract = try CursorCloudAgentAPIContract.createAgentRequest(preview: preview)
        let response: CursorHTTPResponse

        do {
            response = try await transport.data(for: try urlRequest(for: contract, apiKey: apiKey))
        } catch let failure as CursorRuntimeFailure {
            throw failure
        } catch {
            throw CursorRuntimeFailure(message: CursorCloudAgentAPIContract.sanitizedNetworkFailure(error))
        }

        guard (200..<300).contains(response.statusCode) else {
            throw CursorRuntimeFailure(message: CursorCloudAgentAPIContract.sanitizedFailure(
                statusCode: response.statusCode,
                body: response.data
            ))
        }

        do {
            return try CursorCloudAgentAPIContract.decodeCreateAgentResponse(response.data)
        } catch {
            throw CursorRuntimeFailure(message: CursorCloudAgentAPIContract.sanitizedFailure(
                statusCode: response.statusCode,
                body: response.data
            ))
        }
    }

    private func urlRequest(for contract: CursorCloudAgentRequestContract, apiKey: String) throws -> URLRequest {
        let url = baseURL.appending(path: String(contract.path.dropFirst()))
        var request = URLRequest(url: url)
        request.httpMethod = contract.method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Basic \(Data("\(apiKey):".utf8).base64EncodedString())", forHTTPHeaderField: "Authorization")
        request.httpBody = try CursorCloudAgentAPIContract.jsonBodyData(for: contract)
        return request
    }
}
