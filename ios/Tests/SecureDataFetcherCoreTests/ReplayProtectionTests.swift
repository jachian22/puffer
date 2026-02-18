import XCTest
@testable import SecureDataFetcherCore

final class ReplayProtectionTests: XCTestCase {
    func testReplayedNonceIsRejected() async throws {
        let replayStore = InMemoryReplayStore()
        let validator = EnvelopeValidator(sharedSecret: "test_secret", replayStore: replayStore)

        let unsigned = UnsignedRequestEnvelope(
            version: "1",
            requestId: "req-3",
            type: "statement",
            bankId: "default",
            params: EnvelopeParams(month: 1, year: 2026),
            issuedAt: "2026-02-17T00:00:00Z",
            approvalExpiresAt: "2099-02-17T00:05:00Z",
            nonce: "nonce-replay"
        )
        let signature = try Signer.sign(payload: unsigned, secret: "test_secret")
        let envelope = SignedRequestEnvelope(
            version: "1",
            requestId: "req-3",
            type: "statement",
            bankId: "default",
            params: EnvelopeParams(month: 1, year: 2026),
            issuedAt: "2026-02-17T00:00:00Z",
            approvalExpiresAt: "2099-02-17T00:05:00Z",
            nonce: "nonce-replay",
            signature: signature
        )

        try await validator.validate(envelope)

        do {
            try await validator.validate(envelope)
            XCTFail("Expected replay rejection")
        } catch let error as EnvelopeValidationError {
            XCTAssertEqual(error, .replayedNonce)
        }
    }
}
