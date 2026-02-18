import Foundation

public struct EnvelopeValidator {
    private let sharedSecret: String
    private let replayStore: ReplayStore
    private let allowedClockSkewSeconds: TimeInterval

    public init(sharedSecret: String, replayStore: ReplayStore, allowedClockSkewSeconds: TimeInterval = 120) {
        self.sharedSecret = sharedSecret
        self.replayStore = replayStore
        self.allowedClockSkewSeconds = allowedClockSkewSeconds
    }

    public func validate(
        _ envelope: SignedRequestEnvelope,
        now: Date = Date(),
        enforceReplayProtection: Bool = true
    ) async throws {
        guard envelope.version == "1" else {
            throw EnvelopeValidationError.invalidVersion
        }

        let unsigned = UnsignedRequestEnvelope(from: envelope)
        let signatureValid = try Signer.verify(
            payload: unsigned,
            signature: envelope.signature,
            secret: sharedSecret
        )
        guard signatureValid else {
            throw EnvelopeValidationError.invalidSignature
        }

        guard let expiresAt = ISO8601DateFormatter().date(from: envelope.approvalExpiresAt) else {
            throw EnvelopeValidationError.invalidTimestamp
        }

        if now.timeIntervalSince(expiresAt) > allowedClockSkewSeconds {
            throw EnvelopeValidationError.expired
        }

        if enforceReplayProtection {
            if await replayStore.hasSeen(nonce: envelope.nonce) {
                throw EnvelopeValidationError.replayedNonce
            }

            await replayStore.markSeen(nonce: envelope.nonce)
        }
    }
}
