import SwiftUI
import SecureDataFetcherCore

struct RootView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var automationSession: AutomationSessionController

    @State private var bankId = "default"
    @State private var username = ""
    @State private var password = ""

    @State private var brokerBaseURL = ""
    @State private var phoneToken = ""
    @State private var sharedSecret = ""
    @State private var localInboxPath = ""

    @State private var didLoadRuntimeDraft = false

    var body: some View {
        NavigationStack {
            List {
                Section("Runtime") {
                    LabeledContent("Mode", value: model.runtimeMode.rawValue)
                    LabeledContent("Browser Session", value: automationSession.isPresentingWebView ? "Open" : "Idle")

                    if let runtimeMessage = model.runtimeMessage {
                        Text(runtimeMessage)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Runtime Settings") {
                    TextField("Broker base URL", text: $brokerBaseURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    SecureField("Phone API token", text: $phoneToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    SecureField("Broker shared secret", text: $sharedSecret)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    TextField("Local inbox path", text: $localInboxPath)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Button("Use Recommended Inbox Path") {
                        localInboxPath = model.recommendedInboxPath()
                    }
                    .buttonStyle(.bordered)

                    Button("Save Runtime Settings") {
                        model.saveRuntimeSettings(
                            RuntimeSettingsDraft(
                                brokerBaseURL: brokerBaseURL,
                                phoneToken: phoneToken,
                                brokerPhoneSharedSecret: sharedSecret,
                                localInboxPath: localInboxPath
                            )
                        )
                    }
                    .buttonStyle(.borderedProminent)
                }

                Section("Credentials") {
                    TextField("Bank ID", text: $bankId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    SecureField("Password", text: $password)

                    Button("Save Credentials") {
                        model.saveCredentials(bankId: bankId, username: username, password: password)
                        password = ""
                    }
                    .buttonStyle(.borderedProminent)

                    if let message = model.credentialMessage {
                        Text(message)
                            .foregroundStyle(.secondary)
                    }
                }

                if let prompt = automationSession.promptMessage {
                    Section("Manual Verification") {
                        if let challengeKind = automationSession.challengeKindDisplayText {
                            Text("Challenge: \(challengeKind)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text(prompt)

                        HStack {
                            Button("Continue") {
                                automationSession.continueAfterVerification()
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Cancel") {
                                automationSession.cancelVerification()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }

                Section("Actions") {
                    Button("Refresh Pending") {
                        Task { await model.refresh() }
                    }
                }

                Section("Pending Requests") {
                    if model.pendingItems.isEmpty {
                        Text("No pending requests")
                            .foregroundStyle(.secondary)
                    }

                    ForEach(model.pendingItems, id: \.requestId) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Request \(item.requestId)")
                                .font(.headline)
                            Text("\(item.month)/\(item.year) • \(item.bankId)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            HStack {
                                Button("Approve + Execute") {
                                    Task { await model.approveAndExecute(requestId: item.requestId) }
                                }
                                .buttonStyle(.borderedProminent)

                                Button("Deny") {
                                    Task { await model.deny(requestId: item.requestId) }
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                if let completion = model.lastCompletionSummary {
                    Section("Last Completion") {
                        Text(completion)
                    }
                }

                if let error = model.lastError {
                    Section("Last Error") {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Secure Data Fetcher")
            .task {
                if !didLoadRuntimeDraft {
                    let draft = model.loadRuntimeSettingsDraft()
                    brokerBaseURL = draft.brokerBaseURL
                    phoneToken = draft.phoneToken
                    sharedSecret = draft.brokerPhoneSharedSecret
                    localInboxPath = draft.localInboxPath.isEmpty ? model.recommendedInboxPath() : draft.localInboxPath
                    didLoadRuntimeDraft = true
                }

                await model.refresh()
            }
            .sheet(
                isPresented: Binding(
                    get: { automationSession.isPresentingWebView },
                    set: { if !$0 { automationSession.dismissWebView() } }
                )
            ) {
                ExecutionBrowserSheet(session: automationSession)
            }
        }
    }
}

#Preview {
    let model = AppModel.makeLiveOrPreview()
    RootView(model: model, automationSession: model.automationSession)
}
