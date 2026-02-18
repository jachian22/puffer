import Foundation
import XCTest
@testable import SecureDataFetcherCore

private actor MockExecutionAPI: BrokerPhoneAPI {
    private var failures: [(String, ErrorMeta)] = []

    func fetchPendingRequests() async throws -> PendingEnvelopeResponse {
        PendingEnvelopeResponse(requests: [])
    }

    func submitDecision(requestId: String, decision: Decision) async throws -> DecisionResponse {
        DecisionResponse(requestId: requestId, status: "EXECUTING", idempotent: false)
    }

    func submitFailure(requestId: String, error: ErrorMeta) async throws {
        failures.append((requestId, error))
    }

    func submittedFailures() -> [(String, ErrorMeta)] {
        failures
    }
}

private final class MockCredentialStore: CredentialStore {
    var stored: StoredBankCredential?

    init(stored: StoredBankCredential?) {
        self.stored = stored
    }

    func save(_ credential: StoredBankCredential) throws {
        stored = credential
    }

    func load(bankId: String) throws -> StoredBankCredential? {
        guard let stored, stored.bankId == bankId else {
            return nil
        }
        return stored
    }

    func delete(bankId: String) throws {
        if stored?.bankId == bankId {
            stored = nil
        }
    }
}

private struct MockAutomationEngine: StatementAutomationEngine {
    let handler: (StatementRequest, StoredBankCredential, BankScript) async throws -> Data

    func fetchStatement(
        request: StatementRequest,
        credential: StoredBankCredential,
        script: BankScript
    ) async throws -> Data {
        try await handler(request, credential, script)
    }
}

private struct MockCompletionWriter: CompletionWriting {
    let handler: (String, Int, Int, Data) throws -> CompletionWriteResult

    func writeStatementPDF(requestId: String, month: Int, year: Int, pdfData: Data) throws -> CompletionWriteResult {
        try handler(requestId, month, year, pdfData)
    }
}

private func makeEnvelope(requestId: String, secret: String = "shared") throws -> SignedRequestEnvelope {
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

final class ExecutionCoordinatorTests: XCTestCase {
    func testExecuteApprovedSuccessPath() async throws {
        let api = MockExecutionAPI()
        let store = MockCredentialStore(
            stored: StoredBankCredential(bankId: "default", username: "u", password: "p")
        )

        let temp = FileManager.default.temporaryDirectory
        let expected = CompletionWriteResult(
            pdfURL: temp.appendingPathComponent("a.pdf"),
            manifestURL: temp.appendingPathComponent("a.pdf.manifest.json"),
            manifest: CompletionManifest(
                version: "1",
                requestId: "req-success",
                filename: "a.pdf",
                sha256: "abc",
                bytes: 3,
                completedAt: "2026-02-17T00:00:00Z",
                nonce: "n",
                signature: "s"
            )
        )

        let engine = MockAutomationEngine { _, _, _ in
            Data("pdf".utf8)
        }

        let writer = MockCompletionWriter { _, _, _, _ in
            expected
        }

        let coordinator = RequestExecutionCoordinator(
            api: api,
            credentialStore: store,
            automationEngine: engine,
            completionWriter: writer,
            bankScript: ChaseBankScript()
        )

        let envelope = try makeEnvelope(requestId: "req-success")
        let result = try await coordinator.executeApproved(envelope)

        XCTAssertEqual(result, expected)
        let failures = await api.submittedFailures()
        XCTAssertEqual(failures.count, 0)
    }

    func testExecuteApprovedReportsMissingCredentials() async throws {
        let api = MockExecutionAPI()
        let store = MockCredentialStore(stored: nil)

        let engine = MockAutomationEngine { _, _, _ in
            XCTFail("automation should not run when credentials are missing")
            return Data()
        }

        let writer = MockCompletionWriter { _, _, _, _ in
            XCTFail("writer should not run when credentials are missing")
            return CompletionWriteResult(
                pdfURL: URL(fileURLWithPath: "/tmp/nope.pdf"),
                manifestURL: URL(fileURLWithPath: "/tmp/nope.manifest.json"),
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
        }

        let coordinator = RequestExecutionCoordinator(
            api: api,
            credentialStore: store,
            automationEngine: engine,
            completionWriter: writer,
            bankScript: ChaseBankScript()
        )

        let envelope = try makeEnvelope(requestId: "req-missing")

        do {
            _ = try await coordinator.executeApproved(envelope)
            XCTFail("expected missing credentials error")
        } catch let error as RequestExecutionCoordinatorError {
            XCTAssertEqual(error, .credentialsNotFound)
        }

        let failures = await api.submittedFailures()
        XCTAssertEqual(failures.count, 1)
        XCTAssertEqual(failures.first?.0, "req-missing")
        XCTAssertEqual(failures.first?.1.errorCode, "CREDENTIALS_NOT_FOUND")
    }

    func testExecuteApprovedReportsAutomationFailure() async throws {
        let api = MockExecutionAPI()
        let store = MockCredentialStore(
            stored: StoredBankCredential(bankId: "default", username: "u", password: "p")
        )

        let engine = MockAutomationEngine { _, _, _ in
            throw ExecutionFailure.bankLoginFailed
        }

        let writer = MockCompletionWriter { _, _, _, _ in
            XCTFail("writer should not run on automation failure")
            return CompletionWriteResult(
                pdfURL: URL(fileURLWithPath: "/tmp/nope.pdf"),
                manifestURL: URL(fileURLWithPath: "/tmp/nope.manifest.json"),
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
        }

        let coordinator = RequestExecutionCoordinator(
            api: api,
            credentialStore: store,
            automationEngine: engine,
            completionWriter: writer,
            bankScript: ChaseBankScript()
        )

        let envelope = try makeEnvelope(requestId: "req-automation")

        do {
            _ = try await coordinator.executeApproved(envelope)
            XCTFail("expected automation failure")
        } catch let error as RequestExecutionCoordinatorError {
            XCTAssertEqual(error, .automationFailed(.bankLoginFailed))
        }

        let failures = await api.submittedFailures()
        XCTAssertEqual(failures.count, 1)
        XCTAssertEqual(failures.first?.0, "req-automation")
        XCTAssertEqual(failures.first?.1.errorCode, "BANK_LOGIN_FAILED")
    }

    func testExecuteApprovedReportsCompletionWriteFailure() async throws {
        let api = MockExecutionAPI()
        let store = MockCredentialStore(
            stored: StoredBankCredential(bankId: "default", username: "u", password: "p")
        )

        let engine = MockAutomationEngine { _, _, _ in
            Data("pdf".utf8)
        }

        struct WriterFailure: Error {}
        let writer = MockCompletionWriter { _, _, _, _ in
            throw WriterFailure()
        }

        let coordinator = RequestExecutionCoordinator(
            api: api,
            credentialStore: store,
            automationEngine: engine,
            completionWriter: writer,
            bankScript: ChaseBankScript()
        )

        let envelope = try makeEnvelope(requestId: "req-write")

        do {
            _ = try await coordinator.executeApproved(envelope)
            XCTFail("expected completion write failure")
        } catch let error as RequestExecutionCoordinatorError {
            XCTAssertEqual(error, .completionWriteFailed)
        }

        let failures = await api.submittedFailures()
        XCTAssertEqual(failures.count, 1)
        XCTAssertEqual(failures.first?.0, "req-write")
        XCTAssertEqual(failures.first?.1.errorCode, "ICLOUD_WRITE_FAILED")
    }
}
