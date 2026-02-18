import Foundation

public protocol BrokerPhoneAPI {
    func fetchPendingRequests() async throws -> PendingEnvelopeResponse
    func submitDecision(requestId: String, decision: Decision) async throws -> DecisionResponse
    func submitFailure(requestId: String, error: ErrorMeta) async throws
}

extension BrokerAPIClient: BrokerPhoneAPI {}

public actor RequestInbox {
    private var pendingById: [String: SignedRequestEnvelope] = [:]

    public init() {}

    public func replaceAll(with envelopes: [SignedRequestEnvelope]) {
        var next: [String: SignedRequestEnvelope] = [:]
        for envelope in envelopes {
            next[envelope.requestId] = envelope
        }
        pendingById = next
    }

    public func envelope(requestId: String) -> SignedRequestEnvelope? {
        pendingById[requestId]
    }

    public func remove(requestId: String) {
        pendingById.removeValue(forKey: requestId)
    }

    public func all() -> [SignedRequestEnvelope] {
        pendingById.values.sorted { $0.issuedAt < $1.issuedAt }
    }

    public func count() -> Int {
        pendingById.count
    }
}

public struct PendingPollResult: Equatable, Sendable {
    public let fetchedCount: Int
    public let acceptedCount: Int
    public let rejectedCount: Int

    public init(fetchedCount: Int, acceptedCount: Int, rejectedCount: Int) {
        self.fetchedCount = fetchedCount
        self.acceptedCount = acceptedCount
        self.rejectedCount = rejectedCount
    }
}

public struct PendingRequestPoller {
    private let api: BrokerPhoneAPI
    private let inbox: RequestInbox
    private let validator: EnvelopeValidator

    public init(api: BrokerPhoneAPI, inbox: RequestInbox, validator: EnvelopeValidator) {
        self.api = api
        self.inbox = inbox
        self.validator = validator
    }

    public func pollOnce(now: Date = Date()) async throws -> PendingPollResult {
        let pending = try await api.fetchPendingRequests()
        var accepted: [SignedRequestEnvelope] = []
        var rejected = 0

        for item in pending.requests {
            do {
                try await validator.validate(
                    item.envelope,
                    now: now,
                    enforceReplayProtection: false
                )
                accepted.append(item.envelope)
            } catch {
                rejected += 1
            }
        }

        await inbox.replaceAll(with: accepted)

        return PendingPollResult(
            fetchedCount: pending.requests.count,
            acceptedCount: accepted.count,
            rejectedCount: rejected
        )
    }
}

public protocol BiometricAuthorizing {
    func authorize(reason: String) async -> Bool
}

public enum ApprovalCoordinatorError: Error, Equatable {
    case requestNotFound
    case biometricDeclined
}

public struct ApprovalCoordinator {
    private let api: BrokerPhoneAPI
    private let inbox: RequestInbox
    private let validator: EnvelopeValidator
    private let biometric: BiometricAuthorizing

    public init(
        api: BrokerPhoneAPI,
        inbox: RequestInbox,
        validator: EnvelopeValidator,
        biometric: BiometricAuthorizing
    ) {
        self.api = api
        self.inbox = inbox
        self.validator = validator
        self.biometric = biometric
    }

    public func approve(requestId: String, now: Date = Date()) async throws -> DecisionResponse {
        guard let envelope = await inbox.envelope(requestId: requestId) else {
            throw ApprovalCoordinatorError.requestNotFound
        }

        try await validator.validate(envelope, now: now, enforceReplayProtection: true)

        let approved = await biometric.authorize(reason: "Approve statement fetch")
        if !approved {
            throw ApprovalCoordinatorError.biometricDeclined
        }

        let response = try await api.submitDecision(requestId: requestId, decision: .approve)
        await inbox.remove(requestId: requestId)
        return response
    }

    public func deny(requestId: String) async throws -> DecisionResponse {
        guard await inbox.envelope(requestId: requestId) != nil else {
            throw ApprovalCoordinatorError.requestNotFound
        }

        let response = try await api.submitDecision(requestId: requestId, decision: .deny)
        await inbox.remove(requestId: requestId)
        return response
    }

    public func reportFailure(requestId: String, error: ErrorMeta) async throws {
        try await api.submitFailure(requestId: requestId, error: error)
        await inbox.remove(requestId: requestId)
    }
}
