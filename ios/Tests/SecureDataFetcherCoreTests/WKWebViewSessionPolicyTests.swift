import XCTest
@testable import SecureDataFetcherCore

final class WKWebViewSessionPolicyTests: XCTestCase {
    func testMvpWebViewPolicyIsEphemeral() {
        let policy = WebViewSessionPolicy.mvpDefault
        XCTAssertFalse(policy.isPersistent)
        XCTAssertTrue(policy.clearsCookiesPerExecution)
    }
}
