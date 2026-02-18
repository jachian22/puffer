import Foundation
import LocalAuthentication
import XCTest
@testable import SecureDataFetcherCore

private final class MockLAContext: LAContextProtocol {
    let canEvaluate: Bool
    let evaluateResult: Bool

    private(set) var evaluateCalled = false
    private(set) var requestedReason: String?

    init(canEvaluate: Bool, evaluateResult: Bool) {
        self.canEvaluate = canEvaluate
        self.evaluateResult = evaluateResult
    }

    func canEvaluatePolicy(_ policy: LAPolicy, error: NSErrorPointer) -> Bool {
        canEvaluate
    }

    func evaluatePolicy(
        _ policy: LAPolicy,
        localizedReason: String,
        reply: @escaping @Sendable (Bool, Error?) -> Void
    ) {
        evaluateCalled = true
        requestedReason = localizedReason
        reply(evaluateResult, nil)
    }
}

final class BiometricAuthorizerTests: XCTestCase {
    func testAuthorizeReturnsFalseWhenBiometricsUnavailable() async {
        let mock = MockLAContext(canEvaluate: false, evaluateResult: true)
        let authorizer = LABiometricAuthorizer(contextFactory: { mock })

        let result = await authorizer.authorize(reason: "Approve statement fetch")

        XCTAssertFalse(result)
        XCTAssertFalse(mock.evaluateCalled)
    }

    func testAuthorizeReturnsPolicyEvaluationResult() async {
        let mock = MockLAContext(canEvaluate: true, evaluateResult: true)
        let authorizer = LABiometricAuthorizer(contextFactory: { mock })

        let result = await authorizer.authorize(reason: "Approve statement fetch")

        XCTAssertTrue(result)
        XCTAssertTrue(mock.evaluateCalled)
        XCTAssertEqual(mock.requestedReason, "Approve statement fetch")
    }

    func testAuthorizeReturnsFalseWhenEvaluationFails() async {
        let mock = MockLAContext(canEvaluate: true, evaluateResult: false)
        let authorizer = LABiometricAuthorizer(contextFactory: { mock })

        let result = await authorizer.authorize(reason: "Approve statement fetch")

        XCTAssertFalse(result)
        XCTAssertTrue(mock.evaluateCalled)
    }
}
