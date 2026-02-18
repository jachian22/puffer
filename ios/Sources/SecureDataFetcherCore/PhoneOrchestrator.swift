import Foundation

public enum PhoneOrchestratorError: Error, Equatable {
    case requestNotFound
}

public struct PhoneOrchestrator {
    private let inbox: RequestInbox
    private let poller: PendingRequestPoller
    private let approvalCoordinator: ApprovalCoordinator
    private let executionCoordinator: RequestExecutionCoordinator

    public init(
        inbox: RequestInbox,
        poller: PendingRequestPoller,
        approvalCoordinator: ApprovalCoordinator,
        executionCoordinator: RequestExecutionCoordinator
    ) {
        self.inbox = inbox
        self.poller = poller
        self.approvalCoordinator = approvalCoordinator
        self.executionCoordinator = executionCoordinator
    }

    public func refreshPending(now: Date = Date()) async throws -> PendingPollResult {
        try await poller.pollOnce(now: now)
    }

    public func pendingRequests() async -> [SignedRequestEnvelope] {
        await inbox.all()
    }

    @discardableResult
    public func approveAndExecute(
        requestId: String,
        now: Date = Date()
    ) async throws -> CompletionWriteResult {
        guard let envelope = await inbox.envelope(requestId: requestId) else {
            throw PhoneOrchestratorError.requestNotFound
        }

        _ = try await approvalCoordinator.approve(requestId: requestId, now: now)
        return try await executionCoordinator.executeApproved(envelope)
    }

    public func deny(requestId: String) async throws -> DecisionResponse {
        try await approvalCoordinator.deny(requestId: requestId)
    }
}
