import Foundation

@MainActor
public protocol PhoneRuntimeOrchestrating {
    func refreshPending(now: Date) async throws -> PendingPollResult
    func pendingRequests() async -> [SignedRequestEnvelope]
    func approveAndExecute(requestId: String, now: Date) async throws -> CompletionWriteResult
    func deny(requestId: String) async throws -> DecisionResponse
}

extension PhoneOrchestrator: PhoneRuntimeOrchestrating {}

public struct PendingRequestItem: Equatable, Sendable {
    public let requestId: String
    public let bankId: String
    public let month: Int
    public let year: Int
    public let approvalExpiresAt: String

    public init(
        requestId: String,
        bankId: String,
        month: Int,
        year: Int,
        approvalExpiresAt: String
    ) {
        self.requestId = requestId
        self.bankId = bankId
        self.month = month
        self.year = year
        self.approvalExpiresAt = approvalExpiresAt
    }
}

@MainActor
public final class PhoneAppController {
    private let orchestrator: PhoneRuntimeOrchestrating

    public private(set) var pendingItems: [PendingRequestItem] = []
    public private(set) var isRefreshing = false
    public private(set) var isExecuting = false
    public private(set) var lastError: String?
    public private(set) var lastCompletion: CompletionWriteResult?

    public init(orchestrator: PhoneRuntimeOrchestrating) {
        self.orchestrator = orchestrator
    }

    public func refresh(now: Date = Date()) async {
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            _ = try await orchestrator.refreshPending(now: now)
            let envelopes = await orchestrator.pendingRequests()
            pendingItems = envelopes.map(Self.mapItem).sorted { a, b in
                if a.year != b.year { return a.year > b.year }
                if a.month != b.month { return a.month > b.month }
                return a.requestId < b.requestId
            }
            lastError = nil
        } catch {
            lastError = "failed to refresh pending requests"
        }
    }

    public func approveAndExecute(requestId: String, now: Date = Date()) async {
        isExecuting = true
        defer { isExecuting = false }

        do {
            let completion = try await orchestrator.approveAndExecute(requestId: requestId, now: now)
            lastCompletion = completion
            lastError = nil
            pendingItems.removeAll { $0.requestId == requestId }
        } catch {
            lastError = "failed to approve or execute request"
        }
    }

    public func deny(requestId: String) async {
        do {
            _ = try await orchestrator.deny(requestId: requestId)
            pendingItems.removeAll { $0.requestId == requestId }
            lastError = nil
        } catch {
            lastError = "failed to deny request"
        }
    }

    private static func mapItem(_ envelope: SignedRequestEnvelope) -> PendingRequestItem {
        PendingRequestItem(
            requestId: envelope.requestId,
            bankId: envelope.bankId,
            month: envelope.params.month,
            year: envelope.params.year,
            approvalExpiresAt: envelope.approvalExpiresAt
        )
    }
}
