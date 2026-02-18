import Foundation
import XCTest
@testable import SecureDataFetcherCore

@MainActor
private final class MockPhoneRuntimeOrchestrator: PhoneRuntimeOrchestrating {
    var pending: [SignedRequestEnvelope] = []
    var refreshError: Error?
    var approveError: Error?
    var denyError: Error?

    let completionResult: CompletionWriteResult

    init(completionResult: CompletionWriteResult) {
        self.completionResult = completionResult
    }

    func refreshPending(now: Date) async throws -> PendingPollResult {
        if let refreshError {
            throw refreshError
        }
        return PendingPollResult(
            fetchedCount: pending.count,
            acceptedCount: pending.count,
            rejectedCount: 0
        )
    }

    func pendingRequests() async -> [SignedRequestEnvelope] {
        pending
    }

    func approveAndExecute(requestId: String, now: Date) async throws -> CompletionWriteResult {
        if let approveError {
            throw approveError
        }
        pending.removeAll { $0.requestId == requestId }
        return completionResult
    }

    func deny(requestId: String) async throws -> DecisionResponse {
        if let denyError {
            throw denyError
        }
        pending.removeAll { $0.requestId == requestId }
        return DecisionResponse(requestId: requestId, status: "DENIED", idempotent: false)
    }
}

private struct DummyError: Error {}

private func makeControllerEnvelope(requestId: String, secret: String = "shared") throws -> SignedRequestEnvelope {
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

@MainActor
final class PhoneAppControllerTests: XCTestCase {
    func testRefreshLoadsPendingItems() async throws {
        let completion = CompletionWriteResult(
            pdfURL: URL(fileURLWithPath: "/tmp/a.pdf"),
            manifestURL: URL(fileURLWithPath: "/tmp/a.manifest.json"),
            manifest: CompletionManifest(
                version: "1",
                requestId: "req-1",
                filename: "a.pdf",
                sha256: "abc",
                bytes: 3,
                completedAt: "2026-02-17T00:00:00Z",
                nonce: "n",
                signature: "s"
            )
        )

        let mock = MockPhoneRuntimeOrchestrator(completionResult: completion)
        mock.pending.append(try makeControllerEnvelope(requestId: "req-1"))

        let controller = PhoneAppController(orchestrator: mock)

        await controller.refresh()

        XCTAssertEqual(controller.pendingItems.count, 1)
        XCTAssertEqual(controller.pendingItems.first?.requestId, "req-1")
        XCTAssertNil(controller.lastError)
    }

    func testApproveAndExecuteSuccessUpdatesCompletionAndRemovesItem() async throws {
        let completion = CompletionWriteResult(
            pdfURL: URL(fileURLWithPath: "/tmp/b.pdf"),
            manifestURL: URL(fileURLWithPath: "/tmp/b.manifest.json"),
            manifest: CompletionManifest(
                version: "1",
                requestId: "req-2",
                filename: "b.pdf",
                sha256: "def",
                bytes: 3,
                completedAt: "2026-02-17T00:00:00Z",
                nonce: "n2",
                signature: "s2"
            )
        )

        let mock = MockPhoneRuntimeOrchestrator(completionResult: completion)
        mock.pending.append(try makeControllerEnvelope(requestId: "req-2"))

        let controller = PhoneAppController(orchestrator: mock)

        await controller.refresh()
        await controller.approveAndExecute(requestId: "req-2")

        XCTAssertEqual(controller.pendingItems.count, 0)
        XCTAssertEqual(controller.lastCompletion, completion)
        XCTAssertNil(controller.lastError)
    }

    func testApproveAndExecuteFailureSetsError() async throws {
        let completion = CompletionWriteResult(
            pdfURL: URL(fileURLWithPath: "/tmp/c.pdf"),
            manifestURL: URL(fileURLWithPath: "/tmp/c.manifest.json"),
            manifest: CompletionManifest(
                version: "1",
                requestId: "req-3",
                filename: "c.pdf",
                sha256: "ghi",
                bytes: 3,
                completedAt: "2026-02-17T00:00:00Z",
                nonce: "n3",
                signature: "s3"
            )
        )

        let mock = MockPhoneRuntimeOrchestrator(completionResult: completion)
        mock.pending.append(try makeControllerEnvelope(requestId: "req-3"))
        mock.approveError = DummyError()

        let controller = PhoneAppController(orchestrator: mock)

        await controller.refresh()
        await controller.approveAndExecute(requestId: "req-3")

        XCTAssertEqual(controller.lastError, "failed to approve or execute request")
        XCTAssertNil(controller.lastCompletion)
    }

    func testDenyRemovesItem() async throws {
        let completion = CompletionWriteResult(
            pdfURL: URL(fileURLWithPath: "/tmp/d.pdf"),
            manifestURL: URL(fileURLWithPath: "/tmp/d.manifest.json"),
            manifest: CompletionManifest(
                version: "1",
                requestId: "req-4",
                filename: "d.pdf",
                sha256: "jkl",
                bytes: 3,
                completedAt: "2026-02-17T00:00:00Z",
                nonce: "n4",
                signature: "s4"
            )
        )

        let mock = MockPhoneRuntimeOrchestrator(completionResult: completion)
        mock.pending.append(try makeControllerEnvelope(requestId: "req-4"))

        let controller = PhoneAppController(orchestrator: mock)

        await controller.refresh()
        await controller.deny(requestId: "req-4")

        XCTAssertEqual(controller.pendingItems.count, 0)
        XCTAssertNil(controller.lastError)
    }
}
