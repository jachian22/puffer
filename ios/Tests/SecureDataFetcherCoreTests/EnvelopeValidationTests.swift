import XCTest
@testable import SecureDataFetcherCore

final class EnvelopeValidationTests: XCTestCase {
    func testValidEnvelopePassesValidation() async throws {
        let replayStore = InMemoryReplayStore()
        let validator = EnvelopeValidator(sharedSecret: "test_secret", replayStore: replayStore)

        let unsigned = UnsignedRequestEnvelope(
            version: "1",
            requestId: "req-1",
            type: "statement",
            bankId: "default",
            params: EnvelopeParams(month: 1, year: 2026),
            issuedAt: "2026-02-17T00:00:00Z",
            approvalExpiresAt: "2099-02-17T00:05:00Z",
            nonce: "nonce-1"
        )
        let signature = try Signer.sign(payload: unsigned, secret: "test_secret")
        let envelope = SignedRequestEnvelope(
            version: "1",
            requestId: "req-1",
            type: "statement",
            bankId: "default",
            params: EnvelopeParams(month: 1, year: 2026),
            issuedAt: "2026-02-17T00:00:00Z",
            approvalExpiresAt: "2099-02-17T00:05:00Z",
            nonce: "nonce-1",
            signature: signature
        )

        try await validator.validate(envelope)
    }

    func testTamperedEnvelopeFailsValidation() async throws {
        let replayStore = InMemoryReplayStore()
        let validator = EnvelopeValidator(sharedSecret: "test_secret", replayStore: replayStore)

        let unsigned = UnsignedRequestEnvelope(
            version: "1",
            requestId: "req-2",
            type: "statement",
            bankId: "default",
            params: EnvelopeParams(month: 1, year: 2026),
            issuedAt: "2026-02-17T00:00:00Z",
            approvalExpiresAt: "2099-02-17T00:05:00Z",
            nonce: "nonce-2"
        )
        let signature = try Signer.sign(payload: unsigned, secret: "test_secret")
        let envelope = SignedRequestEnvelope(
            version: "1",
            requestId: "req-2",
            type: "statement",
            bankId: "default",
            params: EnvelopeParams(month: 2, year: 2026),
            issuedAt: "2026-02-17T00:00:00Z",
            approvalExpiresAt: "2099-02-17T00:05:00Z",
            nonce: "nonce-2",
            signature: signature
        )

        do {
            try await validator.validate(envelope)
            XCTFail("Expected invalid signature")
        } catch let error as EnvelopeValidationError {
            XCTAssertEqual(error, .invalidSignature)
        }
    }
}
