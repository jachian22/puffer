import Foundation
import LocalAuthentication
import Security

public struct StoredBankCredential: Codable, Equatable, Sendable {
    public let bankId: String
    public let username: String
    public let password: String

    public init(bankId: String, username: String, password: String) {
        self.bankId = bankId
        self.username = username
        self.password = password
    }
}

public enum CredentialStoreError: Error, Equatable {
    case encodingFailed
    case decodingFailed
    case accessControlCreationFailed
    case unexpectedStatus(OSStatus)
}

public protocol CredentialStore {
    func save(_ credential: StoredBankCredential) throws
    func load(bankId: String) throws -> StoredBankCredential?
    func delete(bankId: String) throws
}

public protocol KeychainClient {
    func add(_ query: CFDictionary, _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus
    func update(_ query: CFDictionary, _ attributes: CFDictionary) -> OSStatus
    func copyMatching(_ query: CFDictionary, _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus
    func delete(_ query: CFDictionary) -> OSStatus
}

public struct SystemKeychainClient: KeychainClient {
    public init() {}

    public func add(_ query: CFDictionary, _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
        SecItemAdd(query, result)
    }

    public func update(_ query: CFDictionary, _ attributes: CFDictionary) -> OSStatus {
        SecItemUpdate(query, attributes)
    }

    public func copyMatching(_ query: CFDictionary, _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
        SecItemCopyMatching(query, result)
    }

    public func delete(_ query: CFDictionary) -> OSStatus {
        SecItemDelete(query)
    }
}

public struct KeychainCredentialStore: CredentialStore {
    private let service: String
    private let keychain: KeychainClient
    private let policy: KeychainAccessPolicy

    public init(
        service: String = "com.puffer.secure-data-fetcher.credentials",
        keychain: KeychainClient = SystemKeychainClient(),
        policy: KeychainAccessPolicy = .mvpDefault
    ) {
        self.service = service
        self.keychain = keychain
        self.policy = policy
    }

    public func save(_ credential: StoredBankCredential) throws {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(credential) else {
            throw CredentialStoreError.encodingFailed
        }

        var addQuery = baseQuery(bankId: credential.bankId)
        addQuery[kSecValueData as String] = data
        try applyPolicy(&addQuery)

        let status = keychain.add(addQuery as CFDictionary, nil)
        if status == errSecSuccess {
            return
        }

        if status == errSecDuplicateItem {
            let attrs: [String: Any] = [kSecValueData as String: data]
            let updateStatus = keychain.update(baseQuery(bankId: credential.bankId) as CFDictionary, attrs as CFDictionary)
            if updateStatus == errSecSuccess {
                return
            }
            throw CredentialStoreError.unexpectedStatus(updateStatus)
        }

        throw CredentialStoreError.unexpectedStatus(status)
    }

    public func load(bankId: String) throws -> StoredBankCredential? {
        var query = baseQuery(bankId: bankId)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let context = LAContext()
        context.localizedReason = "Access bank credentials"
        query[kSecUseAuthenticationContext as String] = context

        var result: CFTypeRef?
        let status = keychain.copyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw CredentialStoreError.unexpectedStatus(status)
        }
        guard let data = result as? Data else {
            throw CredentialStoreError.decodingFailed
        }

        let decoder = JSONDecoder()
        guard let decoded = try? decoder.decode(StoredBankCredential.self, from: data) else {
            throw CredentialStoreError.decodingFailed
        }

        return decoded
    }

    public func delete(bankId: String) throws {
        let status = keychain.delete(baseQuery(bankId: bankId) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.unexpectedStatus(status)
        }
    }

    private func baseQuery(bankId: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: bankId,
        ]
    }

    private func applyPolicy(_ query: inout [String: Any]) throws {
        if policy.requiresCurrentBiometricSet {
            var accessError: Unmanaged<CFError>?
            guard let access = SecAccessControlCreateWithFlags(
                nil,
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                .biometryCurrentSet,
                &accessError
            ) else {
                throw CredentialStoreError.accessControlCreationFailed
            }
            query[kSecAttrAccessControl as String] = access
            return
        }

        if policy.accessibleClass == "kSecAttrAccessibleWhenUnlockedThisDeviceOnly" {
            query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }
    }
}

public final class InMemoryCredentialStore: CredentialStore {
    private var credentialsByBankId: [String: StoredBankCredential] = [:]
    private let lock = NSLock()

    public init() {}

    public func save(_ credential: StoredBankCredential) {
        lock.lock()
        defer { lock.unlock() }
        credentialsByBankId[credential.bankId] = credential
    }

    public func load(bankId: String) -> StoredBankCredential? {
        lock.lock()
        defer { lock.unlock() }
        return credentialsByBankId[bankId]
    }

    public func delete(bankId: String) {
        lock.lock()
        defer { lock.unlock() }
        credentialsByBankId.removeValue(forKey: bankId)
    }
}
