import XCTest
@testable import SecureDataFetcherCore

private struct MockTransport: HTTPTransport {
    let handler: (URLRequest) throws -> (Data, URLResponse)

    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try handler(request)
    }
}

final class BrokerAPIClientTests: XCTestCase {
    func testFetchPendingRequestsParsesEnvelope() async throws {
        let responseJson = """
        {
          "requests": [
            {
              "envelope": {
                "version": "1",
                "request_id": "req-1",
                "type": "statement",
                "bank_id": "default",
                "params": { "month": 1, "year": 2026 },
                "issued_at": "2026-02-17T00:00:00Z",
                "approval_expires_at": "2099-02-17T00:05:00Z",
                "nonce": "n1",
                "signature": "sig"
              }
            }
          ]
        }
        """

        let transport = MockTransport { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/v1/phone/requests/pending")
            let data = Data(responseJson.utf8)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (data, response)
        }

        let client = BrokerAPIClient(
            baseURL: URL(string: "http://localhost/")!,
            phoneToken: "token",
            transport: transport
        )

        let pending = try await client.fetchPendingRequests()
        XCTAssertEqual(pending.requests.count, 1)
        XCTAssertEqual(pending.requests.first?.envelope.requestId, "req-1")
    }

    func testSubmitDecisionUsesExpectedPathAndMethod() async throws {
        let responseJson = """
        { "request_id": "req-2", "status": "EXECUTING", "idempotent": false }
        """

        let transport = MockTransport { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/v1/phone/requests/req-2/decision")
            let data = Data(responseJson.utf8)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (data, response)
        }

        let client = BrokerAPIClient(
            baseURL: URL(string: "http://localhost/")!,
            phoneToken: "token",
            transport: transport
        )

        let output = try await client.submitDecision(requestId: "req-2", decision: .approve)
        XCTAssertEqual(output.requestId, "req-2")
        XCTAssertEqual(output.status, "EXECUTING")
        XCTAssertFalse(output.idempotent)
    }
}
