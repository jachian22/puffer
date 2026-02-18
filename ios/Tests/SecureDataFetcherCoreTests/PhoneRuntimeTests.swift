import Foundation
import XCTest
@testable import SecureDataFetcherCore

private actor MockBrokerPhoneAPI: BrokerPhoneAPI {
    var pendingResponse: PendingEnvelopeResponse
    private var decisions: [(String, Decision)] = []
    private var failures: [(String, ErrorMeta)] = []

    init(pendingResponse: PendingEnvelopeResponse) {
        self.pendingResponse = pendingResponse
    }

    func fetchPendingRequests() async throws -> PendingEnvelopeResponse {
        pendingResponse
    }

    func submitDecision(requestId: String, decision: Decision) async throws -> DecisionResponse {
        decisions.append((requestId, decision))
        return DecisionResponse(requestId: requestId, status: "EXECUTING", idempotent: false)
    }

    func submitFailure(requestId: String, error: ErrorMeta) async throws {
        failures.append((requestId, error))
    }

    func submittedDecisions() -> [(String, Decision)] {
        decisions
    }

    func submittedFailures() -> [(String, ErrorMeta)] {
        failures
    }
}

private struct MockBiometric: BiometricAuthorizing {
    let result: Bool

    func authorize(reason: String) async -> Bool {
        result
    }
}

private func makeSignedEnvelope(
    requestId: String,
    nonce: String,
    approvalExpiresAt: String,
    secret: String
) throws -> SignedRequestEnvelope {
    let unsigned = UnsignedRequestEnvelope(
        version: "1",
        requestId: requestId,
        type: "statement",
        bankId: "default",
        params: EnvelopeParams(month: 1, year: 2026),
        issuedAt: "2026-02-17T00:00:00Z",
        approvalExpiresAt: approvalExpiresAt,
        nonce: nonce
    )

    let signature = try Signer.sign(payload: unsigned, secret: secret)
    return SignedRequestEnvelope(
        version: unsigned.version,
        requestId: unsigned.requestId,
        type: unsigned.type,
        bankId: unsigned.bankId,
        params: unsigned.params,
        issuedAt: unsigned.issuedAt,
        approvalExpiresAt: unsigned.approvalExpiresAt,
        nonce: unsigned.nonce,
        signature: signature
    )
}

final class PhoneRuntimeTests: XCTestCase {
    func testPollerAcceptsOnlyValidEnvelopes() async throws {
        let valid = try makeSignedEnvelope(
            requestId: "req-valid",
            nonce: "nonce-valid",
            approvalExpiresAt: "2099-02-17T00:05:00Z",
            secret: "shared"
        )

        let invalid = SignedRequestEnvelope(
            version: valid.version,
            requestId: "req-invalid",
            type: valid.type,
            bankId: valid.bankId,
            params: valid.params,
            issuedAt: valid.issuedAt,
            approvalExpiresAt: valid.approvalExpiresAt,
            nonce: "nonce-invalid",
            signature: "bad-signature"
        )

        let api = MockBrokerPhoneAPI(
            pendingResponse: PendingEnvelopeResponse(
                requests: [
                    .init(envelope: valid),
                    .init(envelope: invalid),
                ]
            )
        )

        let inbox = RequestInbox()
        let validator = EnvelopeValidator(sharedSecret: "shared", replayStore: InMemoryReplayStore())
        let poller = PendingRequestPoller(api: api, inbox: inbox, validator: validator)

        let result = try await poller.pollOnce()
        let inboxCount = await inbox.count()
        let firstId = await inbox.all().first?.requestId

        XCTAssertEqual(result.fetchedCount, 2)
        XCTAssertEqual(result.acceptedCount, 1)
        XCTAssertEqual(result.rejectedCount, 1)
        XCTAssertEqual(inboxCount, 1)
        XCTAssertEqual(firstId, "req-valid")
    }

    func testPollerDoesNotConsumeReplayNonceDuringPolling() async throws {
        let valid = try makeSignedEnvelope(
            requestId: "req-same",
            nonce: "nonce-same",
            approvalExpiresAt: "2099-02-17T00:05:00Z",
            secret: "shared"
        )

        let api = MockBrokerPhoneAPI(
            pendingResponse: PendingEnvelopeResponse(requests: [.init(envelope: valid)])
        )

        let inbox = RequestInbox()
        let validator = EnvelopeValidator(sharedSecret: "shared", replayStore: InMemoryReplayStore())
        let poller = PendingRequestPoller(api: api, inbox: inbox, validator: validator)

        let first = try await poller.pollOnce()
        let second = try await poller.pollOnce()
        let inboxCount = await inbox.count()

        XCTAssertEqual(first.acceptedCount, 1)
        XCTAssertEqual(second.acceptedCount, 1)
        XCTAssertEqual(second.rejectedCount, 0)
        XCTAssertEqual(inboxCount, 1)
    }

    func testApproveRequiresBiometric() async throws {
        let envelope = try makeSignedEnvelope(
            requestId: "req-biometric",
            nonce: "nonce-biometric",
            approvalExpiresAt: "2099-02-17T00:05:00Z",
            secret: "shared"
        )

        let api = MockBrokerPhoneAPI(pendingResponse: PendingEnvelopeResponse(requests: []))
        let inbox = RequestInbox()
        await inbox.replaceAll(with: [envelope])

        let validator = EnvelopeValidator(sharedSecret: "shared", replayStore: InMemoryReplayStore())
        let coordinator = ApprovalCoordinator(
            api: api,
            inbox: inbox,
            validator: validator,
            biometric: MockBiometric(result: false)
        )

        do {
            _ = try await coordinator.approve(requestId: "req-biometric")
            XCTFail("expected biometric decline")
        } catch let error as ApprovalCoordinatorError {
            XCTAssertEqual(error, .biometricDeclined)
        }

        let decisions = await api.submittedDecisions()
        let inboxCount = await inbox.count()
        XCTAssertEqual(decisions.count, 0)
        XCTAssertEqual(inboxCount, 1)
    }

    func testApproveSubmitsDecisionAndRemovesFromInbox() async throws {
        let envelope = try makeSignedEnvelope(
            requestId: "req-approve",
            nonce: "nonce-approve",
            approvalExpiresAt: "2099-02-17T00:05:00Z",
            secret: "shared"
        )

        let api = MockBrokerPhoneAPI(pendingResponse: PendingEnvelopeResponse(requests: []))
        let inbox = RequestInbox()
        await inbox.replaceAll(with: [envelope])

        let validator = EnvelopeValidator(sharedSecret: "shared", replayStore: InMemoryReplayStore())
        let coordinator = ApprovalCoordinator(
            api: api,
            inbox: inbox,
            validator: validator,
            biometric: MockBiometric(result: true)
        )

        let response = try await coordinator.approve(requestId: "req-approve")
        let decisions = await api.submittedDecisions()
        let inboxCount = await inbox.count()

        XCTAssertEqual(response.requestId, "req-approve")
        XCTAssertEqual(decisions.first?.0, "req-approve")
        XCTAssertEqual(decisions.first?.1, .approve)
        XCTAssertEqual(inboxCount, 0)
    }

    func testDenySubmitsDecisionAndRemovesFromInbox() async throws {
        let envelope = try makeSignedEnvelope(
            requestId: "req-deny",
            nonce: "nonce-deny",
            approvalExpiresAt: "2099-02-17T00:05:00Z",
            secret: "shared"
        )

        let api = MockBrokerPhoneAPI(pendingResponse: PendingEnvelopeResponse(requests: []))
        let inbox = RequestInbox()
        await inbox.replaceAll(with: [envelope])

        let validator = EnvelopeValidator(sharedSecret: "shared", replayStore: InMemoryReplayStore())
        let coordinator = ApprovalCoordinator(
            api: api,
            inbox: inbox,
            validator: validator,
            biometric: MockBiometric(result: false)
        )

        let response = try await coordinator.deny(requestId: "req-deny")
        let decisions = await api.submittedDecisions()
        let inboxCount = await inbox.count()

        XCTAssertEqual(response.requestId, "req-deny")
        XCTAssertEqual(decisions.first?.1, .deny)
        XCTAssertEqual(inboxCount, 0)
    }
}
