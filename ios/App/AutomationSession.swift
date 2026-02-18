import Foundation
import SecureDataFetcherCore
import SwiftUI
import WebKit

final class AutomationSessionController: ObservableObject {
    @Published private(set) var isPresentingWebView = false
    @Published private(set) var promptMessage: String?
    @Published private(set) var executionMessage: String?
    @Published private(set) var challengeKind: ManualChallengeKind?
    @Published private(set) var diagnostics: [String] = []

    private let lock = NSLock()
    private var promptContinuation: CheckedContinuation<Bool, Never>?
    private var promptTimeoutTask: Task<Void, Never>?
    private var webView: WKWebView?

    private let maxDiagnosticLines = 120

    deinit {
        resolvePrompt(with: false)
    }

    func prepareWebViewForExecution() -> WKWebView {
        runOnMainSync {
            if self.webView == nil {
                let config = WKWebViewConfiguration()
                config.websiteDataStore = .nonPersistent()
                self.webView = WKWebView(frame: .zero, configuration: config)
            }

            self.diagnostics.removeAll()
            self.promptMessage = nil
            self.challengeKind = nil
            self.isPresentingWebView = true
            self.executionMessage = "Execution in progress..."
            self.appendDiagnostic("INFO", "Execution session started")
            return self.webView!
        }
    }

    func visibleWebView() -> WKWebView? {
        runOnMainSync { self.webView }
    }

    func markExecutionMessage(_ message: String?) {
        runOnMainAsync {
            self.executionMessage = message
            if let message {
                self.appendDiagnostic("UI", message)
            }
        }
    }

    func finishExecution() {
        resolvePrompt(with: false)
        runOnMainAsync {
            self.promptMessage = nil
            self.executionMessage = nil
            self.challengeKind = nil
            self.isPresentingWebView = false
            self.appendDiagnostic("INFO", "Execution session finished")
        }
    }

    func requestUserVerification(
        prompt: String,
        timeout: TimeInterval,
        challengeKind: ManualChallengeKind
    ) async -> Bool {
        runOnMainAsync {
            self.isPresentingWebView = true
            self.promptMessage = prompt
            self.challengeKind = challengeKind
            self.executionMessage = "Waiting for manual verification..."
            self.appendDiagnostic("INFO", "Manual challenge presented: \(challengeKind.rawValue)")
        }

        return await withCheckedContinuation { continuation in
            lock.lock()
            let previous = promptContinuation
            promptContinuation = continuation
            let previousTimeout = promptTimeoutTask
            promptTimeoutTask = nil
            lock.unlock()

            previous?.resume(returning: false)
            previousTimeout?.cancel()

            let timeoutTask = Task { [weak self] in
                guard let self else { return }
                let seconds = max(timeout, 1)
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                self.resolvePrompt(with: false)
                self.runOnMainAsync {
                    self.promptMessage = nil
                    self.challengeKind = nil
                    self.executionMessage = "Verification timed out."
                    self.appendDiagnostic("WARN", "Manual verification timed out")
                }
            }

            lock.lock()
            promptTimeoutTask = timeoutTask
            lock.unlock()
        }
    }

    func continueAfterVerification() {
        resolvePrompt(with: true)
        runOnMainAsync {
            self.promptMessage = nil
            self.challengeKind = nil
            self.executionMessage = "Resuming execution..."
            self.appendDiagnostic("INFO", "User continued after manual verification")
        }
    }

    func cancelVerification() {
        resolvePrompt(with: false)
        runOnMainAsync {
            self.promptMessage = nil
            self.challengeKind = nil
            self.executionMessage = "Verification canceled."
            self.appendDiagnostic("WARN", "User canceled manual verification")
        }
    }

    func dismissWebView() {
        runOnMainAsync {
            self.isPresentingWebView = false
            self.appendDiagnostic("UI", "Execution browser sheet dismissed")
        }
    }

    func recordProgressEvent(_ event: AutomationProgressEvent) {
        runOnMainAsync {
            let level = event.level.rawValue.uppercased()
            if let details = event.details?.trimmingCharacters(in: .whitespacesAndNewlines), !details.isEmpty {
                self.appendDiagnostic(level, "\(event.message) | \(details)")
            } else {
                self.appendDiagnostic(level, event.message)
            }
        }
    }

    var challengeKindDisplayText: String? {
        guard let kind = challengeKind else {
            return nil
        }

        switch kind {
        case .verificationCode:
            return "Verification code"
        case .smsCode:
            return "SMS code"
        case .authenticatorApp:
            return "Authenticator app"
        case .captcha:
            return "Captcha"
        case .securityQuestion:
            return "Security question"
        case .unknown:
            return "Manual verification"
        }
    }

    var recentDiagnostics: [String] {
        Array(diagnostics.suffix(14))
    }

    private func resolvePrompt(with value: Bool) {
        lock.lock()
        let continuation = promptContinuation
        promptContinuation = nil
        let timeoutTask = promptTimeoutTask
        promptTimeoutTask = nil
        lock.unlock()

        timeoutTask?.cancel()
        continuation?.resume(returning: value)
    }

    private func runOnMainAsync(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }

    private func runOnMainSync<T>(_ block: @escaping () -> T) -> T {
        if Thread.isMainThread {
            return block()
        }

        let semaphore = DispatchSemaphore(value: 0)
        var result: T!
        DispatchQueue.main.async {
            result = block()
            semaphore.signal()
        }
        semaphore.wait()
        return result
    }

    private func appendDiagnostic(_ level: String, _ message: String) {
        let timestamp = Self.timestampFormatter.string(from: Date())
        diagnostics.append("[\(timestamp)] [\(level)] \(message)")

        if diagnostics.count > maxDiagnosticLines {
            diagnostics.removeFirst(diagnostics.count - maxDiagnosticLines)
        }
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

final class SessionAutomationProgressReporter: AutomationProgressReporting {
    private weak var session: AutomationSessionController?

    init(session: AutomationSessionController) {
        self.session = session
    }

    func record(_ event: AutomationProgressEvent) {
        session?.recordProgressEvent(event)
    }
}

struct InteractiveTwoFactorHandler: TwoFactorHandling {
    let session: AutomationSessionController

    func waitForUserCompletion(
        requestId: String,
        timeout: TimeInterval,
        challenge: ManualChallenge
    ) async -> Bool {
        let detail = challenge.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let promptPrefix = kindPrefix(challenge.kind)
        let prompt: String

        if detail.isEmpty {
            prompt = "\(promptPrefix) Request \(requestId): complete the challenge, then tap Continue."
        } else {
            prompt = "\(promptPrefix) \(detail) Request \(requestId): tap Continue when done."
        }

        return await session.requestUserVerification(
            prompt: prompt,
            timeout: timeout,
            challengeKind: challenge.kind
        )
    }

    private func kindPrefix(_ kind: ManualChallengeKind) -> String {
        switch kind {
        case .verificationCode:
            return "Verification Code."
        case .smsCode:
            return "SMS Verification."
        case .authenticatorApp:
            return "Authenticator Verification."
        case .captcha:
            return "Captcha Challenge."
        case .securityQuestion:
            return "Security Question."
        case .unknown:
            return "Manual Verification."
        }
    }
}

struct ExecutionBrowserSheet: View {
    @ObservedObject var session: AutomationSessionController

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                if let message = session.executionMessage {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let prompt = session.promptMessage {
                    VStack(alignment: .leading, spacing: 8) {
                        if let challengeKind = session.challengeKindDisplayText {
                            Text("Challenge: \(challengeKind)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text(prompt)
                            .font(.callout)

                        HStack {
                            Button("Continue") {
                                session.continueAfterVerification()
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Cancel") {
                                session.cancelVerification()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !session.recentDiagnostics.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Diagnostics")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ScrollView {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(session.recentDiagnostics.enumerated()), id: \.offset) { _, line in
                                    Text(line)
                                        .font(.caption2)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(minHeight: 90, maxHeight: 150)
                    }
                }

                if let webView = session.visibleWebView() {
                    WebViewContainer(webView: webView)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ProgressView("Preparing browser...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding()
            .navigationTitle("Execution Browser")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        session.dismissWebView()
                    }
                }
            }
        }
    }
}

private struct WebViewContainer: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView {
        webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
