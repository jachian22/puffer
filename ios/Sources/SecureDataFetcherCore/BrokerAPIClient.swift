import Foundation

public struct PendingEnvelopeResponse: Codable, Equatable, Sendable {
    public struct Item: Codable, Equatable, Sendable {
        public let envelope: SignedRequestEnvelope
    }

    public let requests: [Item]
}

public struct DecisionResponse: Codable, Equatable, Sendable {
    public let requestId: String
    public let status: String
    public let idempotent: Bool

    public init(requestId: String, status: String, idempotent: Bool) {
        self.requestId = requestId
        self.status = status
        self.idempotent = idempotent
    }

    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case status
        case idempotent
    }
}

public protocol HTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, URLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    public init() {}

    public func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await URLSession.shared.data(for: request)
    }
}

public struct BrokerAPIClient {
    public let baseURL: URL
    public let phoneToken: String
    public let transport: HTTPTransport

    public init(baseURL: URL, phoneToken: String, transport: HTTPTransport = URLSessionTransport()) {
        self.baseURL = baseURL
        self.phoneToken = phoneToken
        self.transport = transport
    }

    public func fetchPendingRequests() async throws -> PendingEnvelopeResponse {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/phone/requests/pending"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(phoneToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await transport.send(request)
        try validate(response)
        return try JSONDecoder().decode(PendingEnvelopeResponse.self, from: data)
    }

    public func submitDecision(requestId: String, decision: Decision) async throws -> DecisionResponse {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/phone/requests/\(requestId)/decision"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(phoneToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = ["decision": decision.rawValue]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await transport.send(request)
        try validate(response)
        return try JSONDecoder().decode(DecisionResponse.self, from: data)
    }

    public func submitFailure(requestId: String, error: ErrorMeta) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/phone/requests/\(requestId)/failure"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(phoneToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "error_code": error.errorCode,
            "source": error.source.rawValue,
            "stage": error.stage.rawValue,
            "retriable": error.retriable,
            "error_message": error.errorMessage as Any,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (_, response) = try await transport.send(request)
        try validate(response)
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
}
