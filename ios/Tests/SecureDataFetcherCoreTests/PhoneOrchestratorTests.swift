import Foundation
import XCTest
@testable import SecureDataFetcherCore

private actor MockOrchestratorAPI: BrokerPhoneAPI {
    var pendingResponse: PendingEnvelopeResponse
    private var decisions: [(String, Decision)] = []
    private var failures: [(String, ErrorMeta)] = []

    init(pendingResponse: PendingEnvelopeResponse = .init(requests: [])) {
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

private struct AcceptBiometric: BiometricAuthorizing {
    func authorize(reason: String) async -> Bool { true }
}

private final class FixedCredentialStore: CredentialStore {
    private let credential: StoredBankCredential?

    init(_ credential: StoredBankCredential?) {
        self.credential = credential
    }

    func save(_ credential: StoredBankCredential) throws {}
    func load(bankId: String) throws -> StoredBankCredential? { credential }
    func delete(bankId: String) throws {}
}

private struct FixedAutomationEngine: StatementAutomationEngine {
    let data: Data

    func fetchStatement(request: StatementRequest, credential: StoredBankCredential, script: BankScript) async throws -> Data {
        data
    }
}

private struct FixedCompletionWriter: CompletionWriting {
    let result: CompletionWriteResult

    func writeStatementPDF(requestId: String, month: Int, year: Int, pdfData: Data) throws -> CompletionWriteResult {
        result
    }
}

private func makeOrchestratorEnvelope(requestId: String, secret: String = "shared") throws -> SignedRequestEnvelope {
    let unsigned = UnsignedRequestEnvelope(
        version: "1",
        requestId: requestId,
        type: "statement",
        bankId: "default",
        params: EnvelopeParams(month: 1, year: 2026),
        issuedAt: "2026-02-17T00:00:00Z",
        approvalExpiresAt: "2099-02-17T00:05:00Z",
        nonce: "nonce-\(requestId)"
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

final class PhoneOrchestratorTests: XCTestCase {
    func testApproveAndExecuteHappyPath() async throws {
        let api = MockOrchestratorAPI()
        let inbox = RequestInbox()
        let replayStore = InMemoryReplayStore()
        let validator = EnvelopeValidator(sharedSecret: "shared", replayStore: replayStore)
        let poller = PendingRequestPoller(api: api, inbox: inbox, validator: validator)

        let approval = ApprovalCoordinator(
            api: api,
            inbox: inbox,
            validator: validator,
            biometric: AcceptBiometric()
        )

        let expected = CompletionWriteResult(
            pdfURL: URL(fileURLWithPath: "/tmp/out.pdf"),
            manifestURL: URL(fileURLWithPath: "/tmp/out.pdf.manifest.json"),
            manifest: CompletionManifest(
                version: "1",
                requestId: "req-1",
                filename: "out.pdf",
                sha256: "abc",
                bytes: 3,
                completedAt: "2026-02-17T00:00:00Z",
                nonce: "n",
                signature: "s"
            )
        )

        let execution = RequestExecutionCoordinator(
            api: api,
            credentialStore: FixedCredentialStore(.init(bankId: "default", username: "u", password: "p")),
            automationEngine: FixedAutomationEngine(data: Data("pdf".utf8)),
            completionWriter: FixedCompletionWriter(result: expected),
            bankScript: ChaseBankScript()
        )

        let orchestrator = PhoneOrchestrator(
            inbox: inbox,
            poller: poller,
            approvalCoordinator: approval,
            executionCoordinator: execution
        )

        await inbox.replaceAll(with: [try makeOrchestratorEnvelope(requestId: "req-1")])
        let result = try await orchestrator.approveAndExecute(requestId: "req-1")

        XCTAssertEqual(result, expected)
        let decisions = await api.submittedDecisions()
        let failures = await api.submittedFailures()
        XCTAssertEqual(decisions.first?.1, .approve)
        XCTAssertEqual(failures.count, 0)
    }

    func testApproveAndExecuteMissingRequest() async throws {
        let api = MockOrchestratorAPI()
        let inbox = RequestInbox()
        let validator = EnvelopeValidator(sharedSecret: "shared", replayStore: InMemoryReplayStore())
        let poller = PendingRequestPoller(api: api, inbox: inbox, validator: validator)

        let approval = ApprovalCoordinator(
            api: api,
            inbox: inbox,
            validator: validator,
            biometric: AcceptBiometric()
        )

        let execution = RequestExecutionCoordinator(
            api: api,
            credentialStore: FixedCredentialStore(nil),
            automationEngine: FixedAutomationEngine(data: Data()),
            completionWriter: FixedCompletionWriter(
                result: CompletionWriteResult(
                    pdfURL: URL(fileURLWithPath: "/tmp/x"),
                    manifestURL: URL(fileURLWithPath: "/tmp/x.manifest"),
                    manifest: CompletionManifest(
                        version: "1",
                        requestId: "x",
                        filename: "x",
                        sha256: "x",
                        bytes: 1,
                        completedAt: "2026-02-17T00:00:00Z",
                        nonce: "x",
                        signature: "x"
                    )
                )
            ),
            bankScript: ChaseBankScript()
        )

        let orchestrator = PhoneOrchestrator(
            inbox: inbox,
            poller: poller,
            approvalCoordinator: approval,
            executionCoordinator: execution
        )

        do {
            _ = try await orchestrator.approveAndExecute(requestId: "missing")
            XCTFail("expected request not found")
        } catch let error as PhoneOrchestratorError {
            XCTAssertEqual(error, .requestNotFound)
        }
    }
}
