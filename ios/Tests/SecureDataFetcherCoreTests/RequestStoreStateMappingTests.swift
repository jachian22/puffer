import XCTest
@testable import SecureDataFetcherCore

final class RequestStoreStateMappingTests: XCTestCase {
    func testAllowedTransitions() {
        XCTAssertTrue(RequestStateMachine.canTransition(from: .pendingApproval, to: .approved))
        XCTAssertTrue(RequestStateMachine.canTransition(from: .approved, to: .executing))
        XCTAssertTrue(RequestStateMachine.canTransition(from: .executing, to: .completed))
    }

    func testDisallowedTransitions() {
        XCTAssertFalse(RequestStateMachine.canTransition(from: .completed, to: .executing))
        XCTAssertFalse(RequestStateMachine.canTransition(from: .expired, to: .approved))
    }
}
