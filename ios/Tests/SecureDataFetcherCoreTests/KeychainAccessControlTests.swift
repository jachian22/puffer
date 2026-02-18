import XCTest
@testable import SecureDataFetcherCore

final class KeychainAccessControlTests: XCTestCase {
    func testMvpDefaultKeychainPolicy() {
        let policy = KeychainAccessPolicy.mvpDefault
        XCTAssertEqual(policy.accessibleClass, "kSecAttrAccessibleWhenUnlockedThisDeviceOnly")
        XCTAssertTrue(policy.requiresCurrentBiometricSet)
        XCTAssertTrue(policy.deviceOnly)
    }
}
