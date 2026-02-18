# Secure Data Fetcher - Build Status

Last updated: 2026-02-17

## Completed in code

- Broker API (`/v1/request`, `/v1/request/:id`, `/v1/requests`, phone endpoints)
- Broker auth middleware (agent and phone bearer tokens)
- SQLite migrations + state machine guards
- Signed request envelopes and signed completion manifest verification
- iCloud ingestion with periodic reconciliation and best-effort `fs.watch`
- Path traversal and hash mismatch rejection on ingest
- Strict idempotency behavior:
  - same key + same payload => same request returned
  - same key + different payload => `409 IDEMPOTENCY_CONFLICT`
- Telegram request nudge integration (non-blocking)
- Launchd install/uninstall scripts
- Logging + redaction baseline
- iOS core completion writer:
  - hashes PDF bytes
  - signs completion manifest
  - writes PDF + manifest atomically to inbox path
- iOS runtime core for approval flow:
  - `RequestInbox` actor for pending request state
  - `PendingRequestPoller` for broker pending sync + envelope validation
  - `ApprovalCoordinator` with biometric-gated approve and explicit deny/failure actions
- iOS biometric adapter:
  - `LABiometricAuthorizer` with testable `LAContextProtocol` abstraction
- iOS credential storage core:
  - `KeychainCredentialStore` with biometric-bound access-control support
  - `SystemKeychainClient` + testable keychain abstraction
  - `InMemoryCredentialStore` for local/dev wiring
- iOS execution runtime core:
  - `RequestExecutionCoordinator` to run approved request execution
  - wires credentials + automation + completion write
  - reports structured broker failures on execution errors
- iOS automation execution:
  - `ScriptedAutomationEngine` with explicit step sequencing (login, manual challenge pause, navigate, select, download)
  - transient JS evaluation failures during login/2FA polling now degrade to retry-in-loop instead of immediate hard-fail
  - structured progress events emitted during execution for live troubleshooting
  - selector/download failure snapshots captured from page context (`topCandidates`) for debugging
  - typed challenge model (`ManualChallengeKind`, `ManualChallenge`) propagated through 2FA handling
  - driver abstraction (`BankAutomationDriver`, `BankAutomationDriverFactory`)
  - concrete `WKWebViewAutomationDriver` in app target for real foreground execution
  - `AutomationSessionController` for shared visible WebView session and execution status updates
  - `InteractiveTwoFactorHandler` to pause for manual verification with challenge-specific prompts and user Continue/Cancel
  - `ChaseBankScript` credential-injection escaping + selector heuristics for selection/download + challenge descriptor detection
- iOS orchestration/runtime composition:
  - `PhoneOrchestrator` composes pending refresh, approve+execute, and deny flow
  - `PhoneAppController` provides main-actor app-facing state management for refresh/approve/deny
  - `CredentialOnboardingCoordinator` validates and saves onboarding credential input
- iOS app scaffold:
  - SwiftUI app files in `ios/App`
  - XcodeGen spec in `ios/project.yml`
  - setup guide in `ios/APP_SETUP.md`
  - app defaults to live runtime when config exists, otherwise preview fallback
  - runtime settings form (broker URL/token/shared secret/inbox path) and credential onboarding form wired in UI
  - execution browser sheet + manual verification controls wired in UI
  - challenge kind is shown explicitly during manual verification
  - live diagnostics panel shows recent automation events and failure snapshots
- Test coverage:
  - broker unit/integration/security tests
  - root end-to-end request lifecycle tests
  - Swift package core tests for envelope/manifest/state/api/runtime/credential/execution/orchestration/controller/onboarding/automation/script/challenge logic

## Partially implemented

- Chase selector heuristics are intentionally broad and need device-level tightening for reliability across page variants.
- Challenge handling now has typed detection/prompting, but device-specific branch tuning for uncommon challenge pages may still be needed.

## Remaining to reach true MVP completion

- Run device-level selector hardening pass on your real Chase account flows (personal + business surfaces).
- Tune challenge branch UX based on real device observations (captcha/security-question variants, retries, timeout messaging).
- Validate and tune PDF capture reliability from Chase response/download variants.
- Complete end-to-end iPhone validation against broker + iCloud handoff.
- Execute `docs/DEVICE_VALIDATION_RUNBOOK.md` and iterate selectors from captured diagnostics.

## Current verification baseline

- `cd broker && bun test` passes
- `cd broker && bun run typecheck` passes
- `cd ios && swift test` passes
- `cd ios && xcodegen generate` passes
- `cd ios && xcodebuild -project SecureDataFetcher.xcodeproj -scheme SecureDataFetcherApp -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build` passes
- `cd . && bun test e2e/*.test.ts` passes
