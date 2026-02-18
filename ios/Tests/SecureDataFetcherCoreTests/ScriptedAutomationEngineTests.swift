import Foundation
import XCTest
@testable import SecureDataFetcherCore

final class ScriptedAutomationEngineTests: XCTestCase {
    func testFetchStatementHappyPath() async throws {
        let driver = MockBankAutomationDriver(
            booleanResults: [true, true, true, true, true],
            stringResults: [],
            pdfData: Data("pdf".utf8)
        )
        let engine = ScriptedAutomationEngine(
            driverFactory: FixedDriverFactory(driver: driver),
            twoFactorHandler: StubTwoFactorHandler(result: true),
            config: .init(loginTimeout: 2, pollInterval: 0.001, downloadTimeout: 2)
        )

        let result = try await engine.fetchStatement(
            request: StatementRequest(requestId: "req-1", month: 1, year: 2026),
            credential: StoredBankCredential(bankId: "default", username: "u", password: "p"),
            script: ChaseBankScript()
        )

        XCTAssertEqual(result, Data("pdf".utf8))
        XCTAssertEqual(driver.navigatedURLs, [ChaseBankScript().loginURL])
        XCTAssertEqual(driver.evaluatedScripts.count, 5)
        XCTAssertEqual(driver.waitForPDFDownloadCalls, 1)
    }

    func testFetchStatementIgnoresTransientPollingEvaluationFailures() async throws {
        let driver = MockBankAutomationDriver(
            booleanResults: [
                true,  // inject
                false, // 2FA prompt check (loop 1)
                true,  // login success (loop 2)
                true,  // navigate
                true,  // select
                true,  // trigger
            ],
            stringResults: [],
            pdfData: Data("pdf".utf8),
            booleanFailuresAtCallIndices: [1] // login success (loop 1)
        )

        let engine = ScriptedAutomationEngine(
            driverFactory: FixedDriverFactory(driver: driver),
            twoFactorHandler: StubTwoFactorHandler(result: true),
            config: .init(loginTimeout: 2, pollInterval: 0.001, downloadTimeout: 2)
        )

        let result = try await engine.fetchStatement(
            request: StatementRequest(requestId: "req-poll-failure", month: 1, year: 2026),
            credential: StoredBankCredential(bankId: "default", username: "u", password: "p"),
            script: ChaseBankScript()
        )

        XCTAssertEqual(result, Data("pdf".utf8))
    }

    func testFetchStatementRunsTwoFactorPromptPathWithChallengeKind() async throws {
        let twoFactor = StubTwoFactorHandler(result: true)
        let driver = MockBankAutomationDriver(
            booleanResults: [
                true,  // inject
                false, // login success (loop 1)
                true,  // 2FA prompt (loop 1)
                true,  // login success (loop 2)
                true,  // navigate
                true,  // select
                true,  // trigger
            ],
            stringResults: [
                #"{"kind":"sms_code","prompt":"Enter the texted code."}"#,
            ],
            pdfData: Data("pdf".utf8)
        )

        let engine = ScriptedAutomationEngine(
            driverFactory: FixedDriverFactory(driver: driver),
            twoFactorHandler: twoFactor,
            config: .init(loginTimeout: 2, pollInterval: 0.001, downloadTimeout: 2)
        )

        _ = try await engine.fetchStatement(
            request: StatementRequest(requestId: "req-2", month: 1, year: 2026),
            credential: StoredBankCredential(bankId: "default", username: "u", password: "p"),
            script: ChaseBankScript()
        )

        XCTAssertEqual(twoFactor.calls.count, 1)
        XCTAssertEqual(twoFactor.calls[0].requestId, "req-2")
        XCTAssertEqual(twoFactor.calls[0].challenge.kind, .smsCode)
        XCTAssertEqual(twoFactor.calls[0].challenge.prompt, "Enter the texted code.")
    }

    func testFetchStatementTwoFactorFallsBackToUnknownChallengeOnInvalidDescriptor() async throws {
        let twoFactor = StubTwoFactorHandler(result: true)
        let driver = MockBankAutomationDriver(
            booleanResults: [
                true,  // inject
                false, // login success (loop 1)
                true,  // 2FA prompt (loop 1)
                true,  // login success (loop 2)
                true,  // navigate
                true,  // select
                true,  // trigger
            ],
            stringResults: ["not-json"],
            pdfData: Data("pdf".utf8)
        )

        let engine = ScriptedAutomationEngine(
            driverFactory: FixedDriverFactory(driver: driver),
            twoFactorHandler: twoFactor,
            config: .init(loginTimeout: 2, pollInterval: 0.001, downloadTimeout: 2)
        )

        _ = try await engine.fetchStatement(
            request: StatementRequest(requestId: "req-fallback", month: 1, year: 2026),
            credential: StoredBankCredential(bankId: "default", username: "u", password: "p"),
            script: ChaseBankScript()
        )

        XCTAssertEqual(twoFactor.calls.count, 1)
        XCTAssertEqual(twoFactor.calls[0].challenge.kind, .unknown)
    }

    func testFetchStatementReturnsTwoFATimeoutWhenUserDoesNotCompletePrompt() async {
        let twoFactor = StubTwoFactorHandler(result: false)
        let driver = MockBankAutomationDriver(
            booleanResults: [
                true,  // inject
                false, // login success
                true,  // 2FA prompt
            ],
            stringResults: [#"{"kind":"verification_code","prompt":"Enter code."}"#],
            pdfData: Data()
        )

        let engine = ScriptedAutomationEngine(
            driverFactory: FixedDriverFactory(driver: driver),
            twoFactorHandler: twoFactor,
            config: .init(loginTimeout: 2, pollInterval: 0.001, downloadTimeout: 2)
        )

        do {
            _ = try await engine.fetchStatement(
                request: StatementRequest(requestId: "req-3", month: 1, year: 2026),
                credential: StoredBankCredential(bankId: "default", username: "u", password: "p"),
                script: ChaseBankScript()
            )
            XCTFail("expected throw")
        } catch let failure as ExecutionFailure {
            XCTAssertEqual(failure, .twoFATimeout)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testFetchStatementFailsWhenCredentialInjectionReturnsFalse() async {
        let driver = MockBankAutomationDriver(booleanResults: [false], stringResults: [], pdfData: Data())
        let engine = ScriptedAutomationEngine(
            driverFactory: FixedDriverFactory(driver: driver),
            twoFactorHandler: StubTwoFactorHandler(result: true),
            config: .init(loginTimeout: 2, pollInterval: 0.001, downloadTimeout: 2)
        )

        do {
            _ = try await engine.fetchStatement(
                request: StatementRequest(requestId: "req-4", month: 1, year: 2026),
                credential: StoredBankCredential(bankId: "default", username: "u", password: "p"),
                script: ChaseBankScript()
            )
            XCTFail("expected throw")
        } catch let failure as ExecutionFailure {
            XCTAssertEqual(failure, .bankLoginFailed)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testFetchStatementFailsWhenTriggerDownloadReturnsFalse() async {
        let driver = MockBankAutomationDriver(
            booleanResults: [
                true, // inject
                true, // login success
                true, // navigate
                true, // select
                false, // trigger
            ],
            stringResults: [],
            pdfData: Data()
        )

        let engine = ScriptedAutomationEngine(
            driverFactory: FixedDriverFactory(driver: driver),
            twoFactorHandler: StubTwoFactorHandler(result: true),
            config: .init(loginTimeout: 2, pollInterval: 0.001, downloadTimeout: 2)
        )

        do {
            _ = try await engine.fetchStatement(
                request: StatementRequest(requestId: "req-5", month: 1, year: 2026),
                credential: StoredBankCredential(bankId: "default", username: "u", password: "p"),
                script: ChaseBankScript()
            )
            XCTFail("expected throw")
        } catch let failure as ExecutionFailure {
            XCTAssertEqual(failure, .pdfDownloadFailed)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testSelectionFailureEmitsDebugSnapshotEvent() async {
        let reporter = CapturingProgressReporter()
        let driver = MockBankAutomationDriver(
            booleanResults: [
                true, // inject
                true, // login success
                true, // navigate
                false, // select
            ],
            stringResults: [#"{"topCandidates":[{"score":1,"text":"nothing"}]}"#],
            pdfData: Data()
        )

        let engine = ScriptedAutomationEngine(
            driverFactory: FixedDriverFactory(driver: driver),
            twoFactorHandler: StubTwoFactorHandler(result: true),
            config: .init(loginTimeout: 2, pollInterval: 0.001, downloadTimeout: 2),
            progressReporter: reporter
        )

        do {
            _ = try await engine.fetchStatement(
                request: StatementRequest(requestId: "req-debug-select", month: 2, year: 2026),
                credential: StoredBankCredential(bankId: "default", username: "u", password: "p"),
                script: ChaseBankScript()
            )
            XCTFail("expected throw")
        } catch let failure as ExecutionFailure {
            XCTAssertEqual(failure, .navigationFailed)
        } catch {
            XCTFail("unexpected error \(error)")
        }

        let event = reporter.events.first { $0.message.contains("Statement selection did not match") }
        XCTAssertNotNil(event)
        XCTAssertTrue(event?.details?.contains("topCandidates") ?? false)
    }

    func testDownloadFailureEmitsDebugSnapshotEvent() async {
        let reporter = CapturingProgressReporter()
        let driver = MockBankAutomationDriver(
            booleanResults: [
                true, // inject
                true, // login success
                true, // navigate
                true, // select
                false, // trigger
            ],
            stringResults: [#"{"topCandidates":[{"score":2,"text":"view"}]}"#],
            pdfData: Data()
        )

        let engine = ScriptedAutomationEngine(
            driverFactory: FixedDriverFactory(driver: driver),
            twoFactorHandler: StubTwoFactorHandler(result: true),
            config: .init(loginTimeout: 2, pollInterval: 0.001, downloadTimeout: 2),
            progressReporter: reporter
        )

        do {
            _ = try await engine.fetchStatement(
                request: StatementRequest(requestId: "req-debug-download", month: 2, year: 2026),
                credential: StoredBankCredential(bankId: "default", username: "u", password: "p"),
                script: ChaseBankScript()
            )
            XCTFail("expected throw")
        } catch let failure as ExecutionFailure {
            XCTAssertEqual(failure, .pdfDownloadFailed)
        } catch {
            XCTFail("unexpected error \(error)")
        }

        let event = reporter.events.first { $0.message.contains("Download trigger script returned false") }
        XCTAssertNotNil(event)
        XCTAssertTrue(event?.details?.contains("topCandidates") ?? false)
    }
}

private enum MockDriverError: Error {
    case noMoreBooleanResults
    case noMoreStringResults
    case pdfTimeout
    case transientEvalFailure
}

private final class MockBankAutomationDriver: BankAutomationDriver {
    private var remainingBooleanResults: [Bool]
    private var remainingStringResults: [String]
    private let pdfData: Data
    private let booleanFailuresAtCallIndices: Set<Int>
    private var booleanCallCount = 0

    private(set) var navigatedURLs: [URL] = []
    private(set) var evaluatedScripts: [String] = []
    private(set) var evaluatedStringScripts: [String] = []
    private(set) var waitForPDFDownloadCalls = 0

    init(
        booleanResults: [Bool],
        stringResults: [String],
        pdfData: Data,
        booleanFailuresAtCallIndices: Set<Int> = []
    ) {
        self.remainingBooleanResults = booleanResults
        self.remainingStringResults = stringResults
        self.pdfData = pdfData
        self.booleanFailuresAtCallIndices = booleanFailuresAtCallIndices
    }

    func navigate(to url: URL) async throws {
        navigatedURLs.append(url)
    }

    func evaluateBoolean(script: String) async throws -> Bool {
        evaluatedScripts.append(script)

        let callIndex = booleanCallCount
        booleanCallCount += 1
        if booleanFailuresAtCallIndices.contains(callIndex) {
            throw MockDriverError.transientEvalFailure
        }

        guard !remainingBooleanResults.isEmpty else {
            throw MockDriverError.noMoreBooleanResults
        }
        return remainingBooleanResults.removeFirst()
    }

    func evaluateString(script: String) async throws -> String {
        evaluatedStringScripts.append(script)
        guard !remainingStringResults.isEmpty else {
            throw MockDriverError.noMoreStringResults
        }
        return remainingStringResults.removeFirst()
    }

    func waitForPDFDownload(timeout: TimeInterval) async throws -> Data {
        waitForPDFDownloadCalls += 1
        guard !pdfData.isEmpty else {
            throw MockDriverError.pdfTimeout
        }
        return pdfData
    }
}

private struct FixedDriverFactory: BankAutomationDriverFactory {
    let driver: BankAutomationDriver

    func makeDriver() throws -> BankAutomationDriver {
        driver
    }
}

private final class StubTwoFactorHandler: TwoFactorHandling {
    struct Call: Equatable {
        let requestId: String
        let challenge: ManualChallenge
    }

    private let result: Bool
    private(set) var calls: [Call] = []

    init(result: Bool) {
        self.result = result
    }

    func waitForUserCompletion(
        requestId: String,
        timeout: TimeInterval,
        challenge: ManualChallenge
    ) async -> Bool {
        calls.append(Call(requestId: requestId, challenge: challenge))
        return result
    }
}

private final class CapturingProgressReporter: AutomationProgressReporting {
    private(set) var events: [AutomationProgressEvent] = []

    func record(_ event: AutomationProgressEvent) {
        events.append(event)
    }
}
