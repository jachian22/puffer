import Foundation
import SwiftUI
import SecureDataFetcherCore

enum AppRuntimeMode: String {
    case live = "Live"
    case preview = "Preview"
}

struct RuntimeSettingsDraft: Equatable {
    var brokerBaseURL: String
    var phoneToken: String
    var brokerPhoneSharedSecret: String
    var localInboxPath: String

    static let empty = RuntimeSettingsDraft(
        brokerBaseURL: "",
        phoneToken: "",
        brokerPhoneSharedSecret: "",
        localInboxPath: ""
    )
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var runtimeMode: AppRuntimeMode
    @Published private(set) var pendingItems: [PendingRequestItem] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var isExecuting = false
    @Published private(set) var lastError: String?
    @Published private(set) var lastCompletionSummary: String?
    @Published private(set) var credentialMessage: String?
    @Published private(set) var runtimeMessage: String?
    @Published private(set) var automationSession: AutomationSessionController

    private var runtime: AppRuntime
    private let defaults: UserDefaults

    private init(
        runtime: AppRuntime,
        automationSession: AutomationSessionController,
        defaults: UserDefaults = .standard
    ) {
        self.runtime = runtime
        self.runtimeMode = runtime.mode
        self.automationSession = automationSession
        self.defaults = defaults
        syncState()
    }

    func refresh() async {
        await runtime.controller.refresh()
        syncState()
    }

    func approveAndExecute(requestId: String) async {
        await runtime.controller.approveAndExecute(requestId: requestId)
        syncState()
    }

    func deny(requestId: String) async {
        await runtime.controller.deny(requestId: requestId)
        syncState()
    }

    func loadRuntimeSettingsDraft() -> RuntimeSettingsDraft {
        guard let config = AppRuntimeConfig.load(from: defaults) else {
            return .empty
        }

        return RuntimeSettingsDraft(
            brokerBaseURL: config.brokerBaseURL.absoluteString,
            phoneToken: config.phoneToken,
            brokerPhoneSharedSecret: config.brokerPhoneSharedSecret,
            localInboxPath: config.localInboxDirectory.path
        )
    }

    func saveRuntimeSettings(_ draft: RuntimeSettingsDraft) {
        let normalized = RuntimeSettingsDraft(
            brokerBaseURL: draft.brokerBaseURL.trimmingCharacters(in: .whitespacesAndNewlines),
            phoneToken: draft.phoneToken.trimmingCharacters(in: .whitespacesAndNewlines),
            brokerPhoneSharedSecret: draft.brokerPhoneSharedSecret.trimmingCharacters(in: .whitespacesAndNewlines),
            localInboxPath: draft.localInboxPath.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        guard let baseURL = URL(string: normalized.brokerBaseURL),
              let scheme = baseURL.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else {
            runtimeMessage = "Broker base URL must be a valid http(s) URL"
            return
        }

        guard !normalized.phoneToken.isEmpty else {
            runtimeMessage = "Phone API token is required"
            return
        }

        guard !normalized.brokerPhoneSharedSecret.isEmpty else {
            runtimeMessage = "Phone shared secret is required"
            return
        }

        guard !normalized.localInboxPath.isEmpty else {
            runtimeMessage = "Local inbox path is required"
            return
        }

        let config = AppRuntimeConfig(
            brokerBaseURL: baseURL,
            phoneToken: normalized.phoneToken,
            brokerPhoneSharedSecret: normalized.brokerPhoneSharedSecret,
            localInboxDirectory: URL(fileURLWithPath: normalized.localInboxPath, isDirectory: true)
        )
        config.persist(to: defaults)

        reloadRuntime()
        runtimeMessage = runtimeMode == .live
            ? "Runtime settings saved. Live mode enabled."
            : "Runtime settings saved, but app is still in preview mode."
    }

    func saveCredentials(bankId: String, username: String, password: String) {
        do {
            let credential = try runtime.onboarding.saveCredentials(
                bankId: bankId,
                username: username,
                password: password
            )
            credentialMessage = "Saved credentials for \(credential.bankId)"
            lastError = nil
        } catch let error as CredentialOnboardingError {
            switch error {
            case .invalidBankId:
                credentialMessage = "Bank ID is required"
            case .invalidUsername:
                credentialMessage = "Username is required"
            case .invalidPassword:
                credentialMessage = "Password is required"
            }
        } catch {
            credentialMessage = "Failed to save credentials"
        }
    }

    func recommendedInboxPath() -> String {
        if let iCloudDocuments = FileManager.default.url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("SecureFetcher", isDirectory: true)
            .appendingPathComponent("inbox", isDirectory: true) {
            return iCloudDocuments.path
        }

        return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("SecureFetcher", isDirectory: true)
            .appendingPathComponent("inbox", isDirectory: true)
            .path
    }

    private func reloadRuntime() {
        runtime = Self.makeRuntime(defaults: defaults, automationSession: automationSession)
        runtimeMode = runtime.mode
        syncState()
    }

    private func syncState() {
        pendingItems = runtime.controller.pendingItems
        isRefreshing = runtime.controller.isRefreshing
        isExecuting = runtime.controller.isExecuting
        lastError = runtime.controller.lastError

        if let completion = runtime.controller.lastCompletion {
            lastCompletionSummary = "Wrote: \(completion.pdfURL.lastPathComponent)"
        } else {
            lastCompletionSummary = nil
        }
    }
}

extension AppModel {
    static func makeLiveOrPreview(defaults: UserDefaults = .standard) -> AppModel {
        let automationSession = AutomationSessionController()
        let runtime = makeRuntime(defaults: defaults, automationSession: automationSession)
        return AppModel(runtime: runtime, automationSession: automationSession, defaults: defaults)
    }

    private static func makeRuntime(
        defaults: UserDefaults,
        automationSession: AutomationSessionController
    ) -> AppRuntime {
        if let config = AppRuntimeConfig.load(from: defaults) {
            return makeLiveRuntime(config: config, automationSession: automationSession)
        }
        return makePreviewRuntime(automationSession: automationSession)
    }

    private static func makeLiveRuntime(
        config: AppRuntimeConfig,
        automationSession: AutomationSessionController
    ) -> AppRuntime {
        let api = BrokerAPIClient(
            baseURL: config.brokerBaseURL,
            phoneToken: config.phoneToken
        )

        let inbox = RequestInbox()
        let replayStore = InMemoryReplayStore()
        let validator = EnvelopeValidator(
            sharedSecret: config.brokerPhoneSharedSecret,
            replayStore: replayStore
        )

        let poller = PendingRequestPoller(api: api, inbox: inbox, validator: validator)
        let approval = ApprovalCoordinator(
            api: api,
            inbox: inbox,
            validator: validator,
            biometric: LABiometricAuthorizer()
        )

        let credentialStore = KeychainCredentialStore()
        let progressReporter = SessionAutomationProgressReporter(session: automationSession)
        let automation = ScriptedAutomationEngine(
            driverFactory: WKWebViewDriverFactory(session: automationSession),
            twoFactorHandler: InteractiveTwoFactorHandler(session: automationSession),
            config: .mvpDefault,
            progressReporter: progressReporter
        )
        let completionWriter = CompletionArtifactWriter(
            inboxDirectory: config.localInboxDirectory,
            sharedSecret: config.brokerPhoneSharedSecret
        )

        let execution = RequestExecutionCoordinator(
            api: api,
            credentialStore: credentialStore,
            automationEngine: automation,
            completionWriter: completionWriter,
            bankScript: ChaseBankScript()
        )

        let orchestrator = PhoneOrchestrator(
            inbox: inbox,
            poller: poller,
            approvalCoordinator: approval,
            executionCoordinator: execution
        )

        return AppRuntime(
            mode: .live,
            controller: PhoneAppController(orchestrator: orchestrator),
            onboarding: CredentialOnboardingCoordinator(store: credentialStore)
        )
    }

    private static func makePreviewRuntime(
        automationSession: AutomationSessionController
    ) -> AppRuntime {
        automationSession.finishExecution()

        let preview = PreviewOrchestrator()
        let controller = PhoneAppController(orchestrator: preview)
        return AppRuntime(
            mode: .preview,
            controller: controller,
            onboarding: CredentialOnboardingCoordinator(store: InMemoryCredentialStore())
        )
    }
}

private struct AppRuntime {
    let mode: AppRuntimeMode
    let controller: PhoneAppController
    let onboarding: CredentialOnboardingCoordinator
}

private struct AppRuntimeConfig {
    let brokerBaseURL: URL
    let phoneToken: String
    let brokerPhoneSharedSecret: String
    let localInboxDirectory: URL

    static func load(from defaults: UserDefaults = .standard) -> AppRuntimeConfig? {
        guard
            let base = defaults.string(forKey: "broker_base_url"),
            let baseURL = URL(string: base),
            let phoneToken = defaults.string(forKey: "phone_api_token"),
            let sharedSecret = defaults.string(forKey: "broker_phone_shared_secret"),
            let inboxPath = defaults.string(forKey: "local_inbox_path")
        else {
            return nil
        }

        return AppRuntimeConfig(
            brokerBaseURL: baseURL,
            phoneToken: phoneToken,
            brokerPhoneSharedSecret: sharedSecret,
            localInboxDirectory: URL(fileURLWithPath: inboxPath, isDirectory: true)
        )
    }

    func persist(to defaults: UserDefaults = .standard) {
        defaults.set(brokerBaseURL.absoluteString, forKey: "broker_base_url")
        defaults.set(phoneToken, forKey: "phone_api_token")
        defaults.set(brokerPhoneSharedSecret, forKey: "broker_phone_shared_secret")
        defaults.set(localInboxDirectory.path, forKey: "local_inbox_path")
    }
}

@MainActor
private final class PreviewOrchestrator: PhoneRuntimeOrchestrating {
    private var pending: [SignedRequestEnvelope]

    init() {
        let now = ISO8601DateFormatter().string(from: Date())
        pending = [
            SignedRequestEnvelope(
                version: "1",
                requestId: "preview-1",
                type: "statement",
                bankId: "default",
                params: EnvelopeParams(month: 1, year: 2026),
                issuedAt: now,
                approvalExpiresAt: "2099-02-17T00:05:00Z",
                nonce: "preview-nonce",
                signature: "preview"
            )
        ]
    }

    func refreshPending(now: Date) async throws -> PendingPollResult {
        PendingPollResult(fetchedCount: pending.count, acceptedCount: pending.count, rejectedCount: 0)
    }

    func pendingRequests() async -> [SignedRequestEnvelope] {
        pending
    }

    func approveAndExecute(requestId: String, now: Date) async throws -> CompletionWriteResult {
        pending.removeAll { $0.requestId == requestId }
        return CompletionWriteResult(
            pdfURL: URL(fileURLWithPath: "/tmp/\(requestId).pdf"),
            manifestURL: URL(fileURLWithPath: "/tmp/\(requestId).pdf.manifest.json"),
            manifest: CompletionManifest(
                version: "1",
                requestId: requestId,
                filename: "\(requestId).pdf",
                sha256: "preview",
                bytes: 1,
                completedAt: "2026-02-17T00:00:00Z",
                nonce: "preview-complete",
                signature: "preview"
            )
        )
    }

    func deny(requestId: String) async throws -> DecisionResponse {
        pending.removeAll { $0.requestId == requestId }
        return DecisionResponse(requestId: requestId, status: "DENIED", idempotent: false)
    }
}
