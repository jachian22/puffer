import Foundation
import Security
import XCTest
@testable import SecureDataFetcherCore

private final class MockKeychainClient: KeychainClient {
    private var values: [String: Data] = [:]
    var lastAddQuery: [String: Any]?

    private func key(from query: CFDictionary) -> String? {
        guard let dict = query as? [String: Any] else {
            return nil
        }
        guard
            let service = dict[kSecAttrService as String] as? String,
            let account = dict[kSecAttrAccount as String] as? String
        else {
            return nil
        }
        return "\(service)::\(account)"
    }

    func add(_ query: CFDictionary, _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
        guard let dict = query as? [String: Any] else {
            return errSecParam
        }
        lastAddQuery = dict

        guard
            let key = key(from: query),
            let data = dict[kSecValueData as String] as? Data
        else {
            return errSecParam
        }

        if values[key] != nil {
            return errSecDuplicateItem
        }

        values[key] = data
        return errSecSuccess
    }

    func update(_ query: CFDictionary, _ attributes: CFDictionary) -> OSStatus {
        guard
            let key = key(from: query),
            let attrs = attributes as? [String: Any],
            let data = attrs[kSecValueData as String] as? Data
        else {
            return errSecParam
        }

        guard values[key] != nil else {
            return errSecItemNotFound
        }

        values[key] = data
        return errSecSuccess
    }

    func copyMatching(_ query: CFDictionary, _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
        guard let key = key(from: query) else {
            return errSecParam
        }

        guard let data = values[key] else {
            return errSecItemNotFound
        }

        result?.pointee = data as CFData
        return errSecSuccess
    }

    func delete(_ query: CFDictionary) -> OSStatus {
        guard let key = key(from: query) else {
            return errSecParam
        }

        guard values.removeValue(forKey: key) != nil else {
            return errSecItemNotFound
        }
        return errSecSuccess
    }
}

final class CredentialStoreTests: XCTestCase {
    func testKeychainStoreSaveAndLoadRoundTrip() throws {
        let keychain = MockKeychainClient()
        let store = KeychainCredentialStore(service: "test.service", keychain: keychain)

        let input = StoredBankCredential(bankId: "default", username: "u", password: "p")
        try store.save(input)

        let output = try store.load(bankId: "default")
        XCTAssertEqual(output, input)
    }

    func testKeychainStoreDuplicateSaveUpdatesValue() throws {
        let keychain = MockKeychainClient()
        let store = KeychainCredentialStore(service: "test.service", keychain: keychain)

        try store.save(StoredBankCredential(bankId: "default", username: "u1", password: "p1"))
        try store.save(StoredBankCredential(bankId: "default", username: "u2", password: "p2"))

        let output = try store.load(bankId: "default")
        XCTAssertEqual(output?.username, "u2")
        XCTAssertEqual(output?.password, "p2")
    }

    func testKeychainStoreDeleteRemovesCredential() throws {
        let keychain = MockKeychainClient()
        let store = KeychainCredentialStore(service: "test.service", keychain: keychain)

        try store.save(StoredBankCredential(bankId: "default", username: "u", password: "p"))
        try store.delete(bankId: "default")

        let output = try store.load(bankId: "default")
        XCTAssertNil(output)
    }

    func testKeychainStoreMvpPolicyAddsBiometricAccessControl() throws {
        let keychain = MockKeychainClient()
        let store = KeychainCredentialStore(
            service: "test.service",
            keychain: keychain,
            policy: .mvpDefault
        )

        try store.save(StoredBankCredential(bankId: "default", username: "u", password: "p"))

        let addQuery = try XCTUnwrap(keychain.lastAddQuery)
        XCTAssertNotNil(addQuery[kSecAttrAccessControl as String])
    }

    func testInMemoryCredentialStoreRoundTrip() {
        let store = InMemoryCredentialStore()
        let input = StoredBankCredential(bankId: "default", username: "u", password: "p")

        store.save(input)
        let output = store.load(bankId: "default")

        XCTAssertEqual(output, input)

        store.delete(bankId: "default")
        let deleted = store.load(bankId: "default")
        XCTAssertNil(deleted)
    }
}
