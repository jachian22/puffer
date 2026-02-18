import Foundation
import XCTest
@testable import SecureDataFetcherCore

final class CredentialOnboardingCoordinatorTests: XCTestCase {
    func testSaveCredentialsTrimsAndPersists() throws {
        let store = InMemoryCredentialStore()
        let coordinator = CredentialOnboardingCoordinator(store: store)

        let saved = try coordinator.saveCredentials(
            bankId: "  default  ",
            username: "  alice  ",
            password: "  secret  "
        )

        XCTAssertEqual(saved.bankId, "default")
        XCTAssertEqual(saved.username, "alice")
        XCTAssertEqual(saved.password, "secret")

        let loaded = try coordinator.loadCredentials(bankId: "default")
        XCTAssertEqual(loaded, saved)
    }

    func testSaveCredentialsRejectsEmptyBankId() {
        let coordinator = CredentialOnboardingCoordinator(store: InMemoryCredentialStore())

        XCTAssertThrowsError(
            try coordinator.saveCredentials(bankId: "   ", username: "u", password: "p")
        ) { error in
            XCTAssertEqual(error as? CredentialOnboardingError, .invalidBankId)
        }
    }

    func testSaveCredentialsRejectsEmptyUsername() {
        let coordinator = CredentialOnboardingCoordinator(store: InMemoryCredentialStore())

        XCTAssertThrowsError(
            try coordinator.saveCredentials(bankId: "default", username: "  ", password: "p")
        ) { error in
            XCTAssertEqual(error as? CredentialOnboardingError, .invalidUsername)
        }
    }

    func testSaveCredentialsRejectsEmptyPassword() {
        let coordinator = CredentialOnboardingCoordinator(store: InMemoryCredentialStore())

        XCTAssertThrowsError(
            try coordinator.saveCredentials(bankId: "default", username: "u", password: " ")
        ) { error in
            XCTAssertEqual(error as? CredentialOnboardingError, .invalidPassword)
        }
    }
}
