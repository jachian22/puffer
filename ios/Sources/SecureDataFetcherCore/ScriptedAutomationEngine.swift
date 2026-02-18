import Foundation

public enum ManualChallengeKind: String, Codable, Equatable, Sendable {
    case unknown
    case verificationCode = "verification_code"
    case smsCode = "sms_code"
    case authenticatorApp = "authenticator_app"
    case captcha
    case securityQuestion = "security_question"
}

public struct ManualChallenge: Equatable, Sendable {
    public let kind: ManualChallengeKind
    public let prompt: String

    public init(kind: ManualChallengeKind, prompt: String) {
        self.kind = kind
        self.prompt = prompt
    }
}

public struct AutomationProgressEvent: Equatable, Sendable {
    public enum Level: String, Codable, Equatable, Sendable {
        case info
        case warning
    }

    public let level: Level
    public let message: String
    public let details: String?

    public init(level: Level, message: String, details: String? = nil) {
        self.level = level
        self.message = message
        self.details = details
    }
}

public protocol AutomationProgressReporting: AnyObject {
    func record(_ event: AutomationProgressEvent)
}

public protocol BankAutomationDriver {
    func navigate(to url: URL) async throws
    func evaluateBoolean(script: String) async throws -> Bool
    func evaluateString(script: String) async throws -> String
    func waitForPDFDownload(timeout: TimeInterval) async throws -> Data
}

public protocol BankAutomationDriverFactory {
    func makeDriver() throws -> BankAutomationDriver
}

public protocol TwoFactorHandling {
    func waitForUserCompletion(
        requestId: String,
        timeout: TimeInterval,
        challenge: ManualChallenge
    ) async -> Bool
}

public struct ScriptedAutomationConfig: Equatable, Sendable {
    public let loginTimeout: TimeInterval
    public let pollInterval: TimeInterval
    public let downloadTimeout: TimeInterval

    public init(
        loginTimeout: TimeInterval,
        pollInterval: TimeInterval,
        downloadTimeout: TimeInterval
    ) {
        self.loginTimeout = loginTimeout
        self.pollInterval = pollInterval
        self.downloadTimeout = downloadTimeout
    }

    public static let mvpDefault = ScriptedAutomationConfig(
        loginTimeout: 60,
        pollInterval: 1,
        downloadTimeout: 60
    )
}

public struct AlwaysApproveTwoFactorHandler: TwoFactorHandling {
    public init() {}

    public func waitForUserCompletion(
        requestId: String,
        timeout: TimeInterval,
        challenge: ManualChallenge
    ) async -> Bool {
        true
    }
}

public struct ScriptedAutomationEngine: StatementAutomationEngine {
    private let driverFactory: BankAutomationDriverFactory
    private let twoFactorHandler: TwoFactorHandling
    private let config: ScriptedAutomationConfig
    private let progressReporter: AutomationProgressReporting?

    public init(
        driverFactory: BankAutomationDriverFactory,
        twoFactorHandler: TwoFactorHandling,
        config: ScriptedAutomationConfig = .mvpDefault,
        progressReporter: AutomationProgressReporting? = nil
    ) {
        self.driverFactory = driverFactory
        self.twoFactorHandler = twoFactorHandler
        self.config = config
        self.progressReporter = progressReporter
    }

    public func fetchStatement(
        request: StatementRequest,
        credential: StoredBankCredential,
        script: BankScript
    ) async throws -> Data {
        report(.info, "Starting automation run", details: "request_id=\(request.requestId) bank=\(script.bankId) period=\(request.month)/\(request.year)")

        let driver: BankAutomationDriver
        do {
            driver = try driverFactory.makeDriver()
        } catch {
            report(.warning, "Failed to initialize automation driver")
            throw ExecutionFailure.navigationFailed
        }

        report(.info, "Opening bank login URL", details: script.loginURL.absoluteString)
        do {
            try await driver.navigate(to: script.loginURL)
        } catch {
            report(.warning, "Navigation to login URL failed")
            throw ExecutionFailure.navigationFailed
        }

        report(.info, "Injecting credentials into login form")
        let injected = try await eval(script: script.injectCredentials(
            username: credential.username,
            password: credential.password
        ), using: driver, failure: .navigationFailed)
        guard injected else {
            report(.warning, "Credential injection script returned false")
            throw ExecutionFailure.bankLoginFailed
        }

        report(.info, "Waiting for login success / challenge prompt")
        try await waitForLoginSuccess(requestId: request.requestId, script: script, using: driver)

        report(.info, "Navigating to statements view")
        let navigated = try await eval(script: script.navigateToStatements(), using: driver, failure: .navigationFailed)
        guard navigated else {
            report(.warning, "Statements navigation script returned false")
            throw ExecutionFailure.navigationFailed
        }

        report(.info, "Selecting statement", details: "period=\(request.month)/\(request.year)")
        let selected = try await eval(
            script: script.selectStatement(month: request.month, year: request.year),
            using: driver,
            failure: .navigationFailed
        )
        guard selected else {
            let snapshot = await captureSnapshot(
                script: script.debugStatementSelectionSnapshot(month: request.month, year: request.year),
                using: driver
            )
            report(.warning, "Statement selection did not match a clickable candidate", details: snapshot)
            throw ExecutionFailure.navigationFailed
        }

        report(.info, "Triggering statement download")
        let triggered = try await eval(script: script.triggerDownload(), using: driver, failure: .navigationFailed)
        guard triggered else {
            let snapshot = await captureSnapshot(script: script.debugDownloadSnapshot(), using: driver)
            report(.warning, "Download trigger script returned false", details: snapshot)
            throw ExecutionFailure.pdfDownloadFailed
        }

        report(.info, "Waiting for PDF bytes")
        do {
            let pdf = try await driver.waitForPDFDownload(timeout: config.downloadTimeout)
            report(.info, "PDF bytes captured", details: "bytes=\(pdf.count)")
            return pdf
        } catch {
            report(.warning, "PDF download timed out or failed")
            throw ExecutionFailure.pdfDownloadFailed
        }
    }

    private func waitForLoginSuccess(
        requestId: String,
        script: BankScript,
        using driver: BankAutomationDriver
    ) async throws {
        let deadline = Date().addingTimeInterval(config.loginTimeout)
        let pollInterval = max(config.pollInterval, 0.1)
        var twoFactorPrompted = false

        while Date() < deadline {
            let loggedIn = await evalForPolling(script: script.detectLoginSuccess(), using: driver)
            if loggedIn {
                report(.info, "Login success detected")
                return
            }

            let needsTwoFactor = await evalForPolling(script: script.detectTwoFactorPrompt(), using: driver)
            if needsTwoFactor {
                twoFactorPrompted = true
                let remaining = max(deadline.timeIntervalSinceNow, 1)
                let challenge = await detectManualChallenge(script: script, using: driver)
                report(.info, "Manual challenge detected", details: "kind=\(challenge.kind.rawValue) prompt=\(challenge.prompt)")
                let completed = await twoFactorHandler.waitForUserCompletion(
                    requestId: requestId,
                    timeout: remaining,
                    challenge: challenge
                )
                if !completed {
                    report(.warning, "Manual challenge was not completed before timeout")
                    throw ExecutionFailure.twoFATimeout
                }
            }

            do {
                try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
            } catch {
                report(.warning, "Execution task interrupted while waiting for login")
                throw ExecutionFailure.executionTimeout
            }
        }
        if twoFactorPrompted {
            report(.warning, "2FA challenge timed out before login success")
            throw ExecutionFailure.twoFATimeout
        }
        report(.warning, "Login did not complete before timeout without explicit challenge")
        throw ExecutionFailure.bankLoginFailed
    }

    private func evalForPolling(
        script: String,
        using driver: BankAutomationDriver
    ) async -> Bool {
        do {
            return try await driver.evaluateBoolean(script: script)
        } catch {
            return false
        }
    }

    private func detectManualChallenge(
        script: BankScript,
        using driver: BankAutomationDriver
    ) async -> ManualChallenge {
        let fallback = ManualChallenge(
            kind: .unknown,
            prompt: "Complete verification in the browser, then continue."
        )

        let descriptorRaw: String
        do {
            descriptorRaw = try await driver.evaluateString(script: script.detectManualChallengeDescriptor())
        } catch {
            report(.warning, "Challenge descriptor evaluation failed; using fallback")
            return fallback
        }

        guard !descriptorRaw.isEmpty else {
            report(.warning, "Challenge descriptor was empty; using fallback")
            return fallback
        }

        guard
            let data = descriptorRaw.data(using: .utf8),
            let decoded = try? JSONDecoder().decode(ChallengeDescriptor.self, from: data)
        else {
            report(.warning, "Challenge descriptor decode failed; using fallback", details: clip(descriptorRaw))
            return fallback
        }

        let kind = decoded.kind ?? .unknown
        let prompt = decoded.prompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if prompt.isEmpty {
            return ManualChallenge(kind: kind, prompt: defaultPrompt(for: kind))
        }

        return ManualChallenge(kind: kind, prompt: prompt)
    }

    private func defaultPrompt(for kind: ManualChallengeKind) -> String {
        switch kind {
        case .verificationCode:
            return "Enter the verification code shown by your bank, then continue."
        case .smsCode:
            return "Enter the SMS verification code from your bank, then continue."
        case .authenticatorApp:
            return "Open your authenticator app, enter the code, then continue."
        case .captcha:
            return "Complete the captcha challenge in browser, then continue."
        case .securityQuestion:
            return "Answer the security question in browser, then continue."
        case .unknown:
            return "Complete verification in the browser, then continue."
        }
    }

    private func eval(
        script: String,
        using driver: BankAutomationDriver,
        failure: ExecutionFailure
    ) async throws -> Bool {
        do {
            return try await driver.evaluateBoolean(script: script)
        } catch {
            throw failure
        }
    }

    private func captureSnapshot(
        script: String,
        using driver: BankAutomationDriver
    ) async -> String? {
        guard !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        do {
            let raw = try await driver.evaluateString(script: script)
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return nil
            }
            return clip(trimmed)
        } catch {
            return nil
        }
    }

    private func clip(_ value: String, maxLength: Int = 1200) -> String {
        if value.count <= maxLength {
            return value
        }

        let end = value.index(value.startIndex, offsetBy: maxLength)
        return String(value[..<end]) + "..."
    }

    private func report(_ level: AutomationProgressEvent.Level, _ message: String, details: String? = nil) {
        progressReporter?.record(AutomationProgressEvent(level: level, message: message, details: details))
    }
}

private struct ChallengeDescriptor: Decodable {
    let kind: ManualChallengeKind?
    let prompt: String?
}
