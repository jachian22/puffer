import Foundation

public enum RequestStatus: String, Codable, CaseIterable, Sendable {
    case pendingApproval = "PENDING_APPROVAL"
    case approved = "APPROVED"
    case executing = "EXECUTING"
    case completed = "COMPLETED"
    case failed = "FAILED"
    case denied = "DENIED"
    case expired = "EXPIRED"
}

public enum Decision: String, Codable, Sendable {
    case approve = "APPROVE"
    case deny = "DENY"
}

public enum ErrorSource: String, Codable, Sendable {
    case broker = "BROKER"
    case phone = "PHONE"
    case bank = "BANK"
    case iCloud = "ICLOUD"
}

public enum ErrorStage: String, Codable, Sendable {
    case approval = "APPROVAL"
    case auth = "AUTH"
    case navigation = "NAVIGATION"
    case download = "DOWNLOAD"
    case ingest = "INGEST"
    case verify = "VERIFY"
}

public struct ErrorMeta: Codable, Equatable, Sendable {
    public let errorCode: String
    public let source: ErrorSource
    public let stage: ErrorStage
    public let retriable: Bool
    public let errorMessage: String?

    public init(errorCode: String, source: ErrorSource, stage: ErrorStage, retriable: Bool, errorMessage: String? = nil) {
        self.errorCode = errorCode
        self.source = source
        self.stage = stage
        self.retriable = retriable
        self.errorMessage = errorMessage
    }
}

public struct EnvelopeParams: Codable, Equatable, Sendable {
    public let month: Int
    public let year: Int

    public init(month: Int, year: Int) {
        self.month = month
        self.year = year
    }
}

public struct SignedRequestEnvelope: Codable, Equatable, Sendable {
    public let version: String
    public let requestId: String
    public let type: String
    public let bankId: String
    public let params: EnvelopeParams
    public let issuedAt: String
    public let approvalExpiresAt: String
    public let nonce: String
    public let signature: String

    public init(version: String, requestId: String, type: String, bankId: String, params: EnvelopeParams, issuedAt: String, approvalExpiresAt: String, nonce: String, signature: String) {
        self.version = version
        self.requestId = requestId
        self.type = type
        self.bankId = bankId
        self.params = params
        self.issuedAt = issuedAt
        self.approvalExpiresAt = approvalExpiresAt
        self.nonce = nonce
        self.signature = signature
    }

    enum CodingKeys: String, CodingKey {
        case version
        case requestId = "request_id"
        case type
        case bankId = "bank_id"
        case params
        case issuedAt = "issued_at"
        case approvalExpiresAt = "approval_expires_at"
        case nonce
        case signature
    }
}

public struct UnsignedRequestEnvelope: Codable, Equatable, Sendable {
    public let version: String
    public let requestId: String
    public let type: String
    public let bankId: String
    public let params: EnvelopeParams
    public let issuedAt: String
    public let approvalExpiresAt: String
    public let nonce: String

    public init(version: String, requestId: String, type: String, bankId: String, params: EnvelopeParams, issuedAt: String, approvalExpiresAt: String, nonce: String) {
        self.version = version
        self.requestId = requestId
        self.type = type
        self.bankId = bankId
        self.params = params
        self.issuedAt = issuedAt
        self.approvalExpiresAt = approvalExpiresAt
        self.nonce = nonce
    }

    public init(from signed: SignedRequestEnvelope) {
        self.version = signed.version
        self.requestId = signed.requestId
        self.type = signed.type
        self.bankId = signed.bankId
        self.params = signed.params
        self.issuedAt = signed.issuedAt
        self.approvalExpiresAt = signed.approvalExpiresAt
        self.nonce = signed.nonce
    }

    enum CodingKeys: String, CodingKey {
        case version
        case requestId = "request_id"
        case type
        case bankId = "bank_id"
        case params
        case issuedAt = "issued_at"
        case approvalExpiresAt = "approval_expires_at"
        case nonce
    }
}

public struct CompletionManifest: Codable, Equatable, Sendable {
    public let version: String
    public let requestId: String
    public let filename: String
    public let sha256: String
    public let bytes: Int
    public let completedAt: String
    public let nonce: String
    public let signature: String

    public init(version: String, requestId: String, filename: String, sha256: String, bytes: Int, completedAt: String, nonce: String, signature: String) {
        self.version = version
        self.requestId = requestId
        self.filename = filename
        self.sha256 = sha256
        self.bytes = bytes
        self.completedAt = completedAt
        self.nonce = nonce
        self.signature = signature
    }

    enum CodingKeys: String, CodingKey {
        case version
        case requestId = "request_id"
        case filename
        case sha256
        case bytes
        case completedAt = "completed_at"
        case nonce
        case signature
    }
}

public struct UnsignedCompletionManifest: Codable, Equatable, Sendable {
    public let version: String
    public let requestId: String
    public let filename: String
    public let sha256: String
    public let bytes: Int
    public let completedAt: String
    public let nonce: String

    public init(version: String, requestId: String, filename: String, sha256: String, bytes: Int, completedAt: String, nonce: String) {
        self.version = version
        self.requestId = requestId
        self.filename = filename
        self.sha256 = sha256
        self.bytes = bytes
        self.completedAt = completedAt
        self.nonce = nonce
    }

    public init(from signed: CompletionManifest) {
        self.version = signed.version
        self.requestId = signed.requestId
        self.filename = signed.filename
        self.sha256 = signed.sha256
        self.bytes = signed.bytes
        self.completedAt = signed.completedAt
        self.nonce = signed.nonce
    }

    enum CodingKeys: String, CodingKey {
        case version
        case requestId = "request_id"
        case filename
        case sha256
        case bytes
        case completedAt = "completed_at"
        case nonce
    }
}

public enum EnvelopeValidationError: Error, Equatable, Sendable {
    case invalidSignature
    case invalidVersion
    case expired
    case replayedNonce
    case invalidTimestamp
}
