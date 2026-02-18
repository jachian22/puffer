import Foundation

public protocol StatementAutomationEngine {
    func fetchStatement(
        request: StatementRequest,
        credential: StoredBankCredential,
        script: BankScript
    ) async throws -> Data
}

public protocol CompletionWriting {
    func writeStatementPDF(
        requestId: String,
        month: Int,
        year: Int,
        pdfData: Data
    ) throws -> CompletionWriteResult
}

extension CompletionArtifactWriter: CompletionWriting {}

public enum RequestExecutionCoordinatorError: Error, Equatable {
    case invalidRequestType
    case credentialsNotFound
    case automationFailed(ExecutionFailure)
    case completionWriteFailed
}

public struct RequestExecutionCoordinator {
    private let api: BrokerPhoneAPI
    private let credentialStore: CredentialStore
    private let automationEngine: StatementAutomationEngine
    private let completionWriter: CompletionWriting
    private let bankScript: BankScript

    public init(
        api: BrokerPhoneAPI,
        credentialStore: CredentialStore,
        automationEngine: StatementAutomationEngine,
        completionWriter: CompletionWriting,
        bankScript: BankScript
    ) {
        self.api = api
        self.credentialStore = credentialStore
        self.automationEngine = automationEngine
        self.completionWriter = completionWriter
        self.bankScript = bankScript
    }

    @discardableResult
    public func executeApproved(_ envelope: SignedRequestEnvelope) async throws -> CompletionWriteResult {
        guard envelope.type == "statement" else {
            let meta = ErrorMeta(
                errorCode: "INVALID_REQUEST_TYPE",
                source: .phone,
                stage: .navigation,
                retriable: false,
                errorMessage: "unsupported request type"
            )
            try await api.submitFailure(requestId: envelope.requestId, error: meta)
            throw RequestExecutionCoordinatorError.invalidRequestType
        }

        guard let credential = try credentialStore.load(bankId: envelope.bankId) else {
            let meta = ExecutionErrorMapper.map(.credentialsNotFound)
            try await api.submitFailure(requestId: envelope.requestId, error: meta)
            throw RequestExecutionCoordinatorError.credentialsNotFound
        }

        let request = StatementRequest(
            requestId: envelope.requestId,
            month: envelope.params.month,
            year: envelope.params.year
        )

        let pdfData: Data
        do {
            pdfData = try await automationEngine.fetchStatement(
                request: request,
                credential: credential,
                script: bankScript
            )
        } catch let failure as ExecutionFailure {
            let meta = ExecutionErrorMapper.map(failure)
            try await api.submitFailure(requestId: envelope.requestId, error: meta)
            throw RequestExecutionCoordinatorError.automationFailed(failure)
        } catch {
            let meta = ExecutionErrorMapper.map(
                .navigationFailed,
                message: "unexpected automation error"
            )
            try await api.submitFailure(requestId: envelope.requestId, error: meta)
            throw RequestExecutionCoordinatorError.automationFailed(.navigationFailed)
        }

        do {
            return try completionWriter.writeStatementPDF(
                requestId: envelope.requestId,
                month: envelope.params.month,
                year: envelope.params.year,
                pdfData: pdfData
            )
        } catch {
            let meta = ExecutionErrorMapper.map(.iCloudWriteFailed)
            try await api.submitFailure(requestId: envelope.requestId, error: meta)
            throw RequestExecutionCoordinatorError.completionWriteFailed
        }
    }
}
