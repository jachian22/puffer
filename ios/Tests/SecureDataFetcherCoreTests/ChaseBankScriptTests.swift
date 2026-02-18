import XCTest
@testable import SecureDataFetcherCore

final class ChaseBankScriptTests: XCTestCase {
    func testInjectCredentialsEscapesSpecialCharacters() {
        let script = ChaseBankScript().injectCredentials(
            username: "user\"name",
            password: "pa\\ss"
        )

        XCTAssertTrue(script.contains("user\\\"name"))
        XCTAssertTrue(script.contains("pa\\\\ss"))
        XCTAssertTrue(script.contains("dispatchEvent(new Event('input'"))
    }

    func testSelectStatementScriptUsesRequestedPeriod() {
        let script = ChaseBankScript().selectStatement(month: 12, year: 2026)

        XCTAssertTrue(script.contains("12"))
        XCTAssertTrue(script.contains("2026"))
        XCTAssertTrue(script.contains("bestScore"))
        XCTAssertTrue(script.contains("credit card"))
    }

    func testChallengeDescriptorScriptContainsKnownChallengeKinds() {
        let script = ChaseBankScript().detectManualChallengeDescriptor()

        XCTAssertTrue(script.contains("captcha"))
        XCTAssertTrue(script.contains("security_question"))
        XCTAssertTrue(script.contains("authenticator_app"))
        XCTAssertTrue(script.contains("sms_code"))
        XCTAssertTrue(script.contains("verification_code"))
        XCTAssertTrue(script.contains("JSON.stringify"))
    }

    func testTwoFactorPromptScriptChecksInputSignalsAndCaptcha() {
        let script = ChaseBankScript().detectTwoFactorPrompt()

        XCTAssertTrue(script.contains("one-time-code"))
        XCTAssertTrue(script.contains("recaptcha"))
        XCTAssertTrue(script.contains("security question"))
    }

    func testSelectionDebugSnapshotScriptContainsTopCandidatesAndTarget() {
        let script = ChaseBankScript().debugStatementSelectionSnapshot(month: 2, year: 2026)

        XCTAssertTrue(script.contains("topCandidates"))
        XCTAssertTrue(script.contains("target"))
        XCTAssertTrue(script.contains("month"))
        XCTAssertTrue(script.contains("year"))
    }

    func testDownloadDebugSnapshotScriptContainsTopCandidates() {
        let script = ChaseBankScript().debugDownloadSnapshot()

        XCTAssertTrue(script.contains("topCandidates"))
        XCTAssertTrue(script.contains("url"))
        XCTAssertTrue(script.contains("score"))
    }
}
