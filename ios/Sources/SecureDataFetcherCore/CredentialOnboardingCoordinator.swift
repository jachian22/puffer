import Foundation

public enum CredentialOnboardingError: Error, Equatable {
    case invalidBankId
    case invalidUsername
    case invalidPassword
}

public struct CredentialOnboardingCoordinator {
    private let store: CredentialStore

    public init(store: CredentialStore) {
        self.store = store
    }

    @discardableResult
    public func saveCredentials(
        bankId: String,
        username: String,
        password: String
    ) throws -> StoredBankCredential {
        let normalizedBankId = bankId.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedBankId.isEmpty else {
            throw CredentialOnboardingError.invalidBankId
        }
        guard !normalizedUsername.isEmpty else {
            throw CredentialOnboardingError.invalidUsername
        }
        guard !normalizedPassword.isEmpty else {
            throw CredentialOnboardingError.invalidPassword
        }

        let credential = StoredBankCredential(
            bankId: normalizedBankId,
            username: normalizedUsername,
            password: normalizedPassword
        )

        try store.save(credential)
        return credential
    }

    public func loadCredentials(bankId: String) throws -> StoredBankCredential? {
        try store.load(bankId: bankId)
    }
}
