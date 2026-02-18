import XCTest
@testable import SecureDataFetcherCore

final class ExecutionErrorMappingTests: XCTestCase {
    func testNavigationFailureMapping() {
        let mapped = ExecutionErrorMapper.map(.navigationFailed)
        XCTAssertEqual(mapped.errorCode, "NAVIGATION_FAILED")
        XCTAssertEqual(mapped.source, .phone)
        XCTAssertEqual(mapped.stage, .navigation)
        XCTAssertTrue(mapped.retriable)
    }

    func testTwoFATimeoutMapping() {
        let mapped = ExecutionErrorMapper.map(.twoFATimeout)
        XCTAssertEqual(mapped.errorCode, "BANK_2FA_TIMEOUT")
        XCTAssertEqual(mapped.source, .bank)
        XCTAssertEqual(mapped.stage, .auth)
        XCTAssertTrue(mapped.retriable)
    }
}
