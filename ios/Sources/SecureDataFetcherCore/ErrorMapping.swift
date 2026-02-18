import Foundation

public enum ExecutionFailure: Error, Equatable, Sendable {
    case bankLoginFailed
    case twoFATimeout
    case navigationFailed
    case pdfDownloadFailed
    case iCloudWriteFailed
    case executionTimeout
    case credentialsNotFound
}

public enum ExecutionErrorMapper {
    public static func map(_ failure: ExecutionFailure, message: String? = nil) -> ErrorMeta {
        switch failure {
        case .bankLoginFailed:
            return ErrorMeta(errorCode: "BANK_LOGIN_FAILED", source: .bank, stage: .auth, retriable: false, errorMessage: message)
        case .twoFATimeout:
            return ErrorMeta(errorCode: "BANK_2FA_TIMEOUT", source: .bank, stage: .auth, retriable: true, errorMessage: message)
        case .navigationFailed:
            return ErrorMeta(errorCode: "NAVIGATION_FAILED", source: .phone, stage: .navigation, retriable: true, errorMessage: message)
        case .pdfDownloadFailed:
            return ErrorMeta(errorCode: "PDF_DOWNLOAD_FAILED", source: .bank, stage: .download, retriable: true, errorMessage: message)
        case .iCloudWriteFailed:
            return ErrorMeta(errorCode: "ICLOUD_WRITE_FAILED", source: .iCloud, stage: .ingest, retriable: true, errorMessage: message)
        case .executionTimeout:
            return ErrorMeta(errorCode: "EXECUTION_TIMEOUT", source: .phone, stage: .download, retriable: true, errorMessage: message)
        case .credentialsNotFound:
            return ErrorMeta(errorCode: "CREDENTIALS_NOT_FOUND", source: .phone, stage: .auth, retriable: false, errorMessage: message)
        }
    }
}
