# iOS App Setup (Scaffold)

This repo includes a SwiftUI app in `ios/App` and an XcodeGen spec in `ios/project.yml`.

## 1) Generate Xcode project

From `ios/`:

```bash
xcodegen generate
```

This creates `SecureDataFetcher.xcodeproj` with app target `SecureDataFetcherApp`.

## 2) Open and run

```bash
open SecureDataFetcher.xcodeproj
```

Select an iPhone simulator or device and run `SecureDataFetcherApp`.

## 3) Current behavior

- Boots in `Live` mode when runtime settings exist in `UserDefaults`; otherwise boots in `Preview` mode.
- Includes in-app runtime settings form for:
  - broker base URL
  - phone API token
  - phone shared secret
  - local inbox path
- Includes credential onboarding form wired to `CredentialOnboardingCoordinator`.
- Live execution uses:
  - `ScriptedAutomationEngine`
  - `WKWebViewDriverFactory` / `WKWebViewAutomationDriver`
  - `AutomationSessionController` for visible browser session and execution status
  - `InteractiveTwoFactorHandler` for manual verification prompts with challenge-type-specific messaging
  - `SessionAutomationProgressReporter` + diagnostics panel in `Execution Browser` for step-by-step troubleshooting
  - `ChaseBankScript` heuristic selectors for statement selection/download and challenge descriptor detection, plus debug snapshots on failure
- Supports refresh, approve+execute, and deny from the pending request list.

## 4) Remaining wiring steps

- Harden Chase selectors after device-level runs (both personal and business statement surfaces).
- Add richer challenge-branch UX for specific captcha/security-question edge cases if needed after device testing.
- Validate end-to-end on physical iPhone against broker and iCloud sync.
- Use `docs/DEVICE_VALIDATION_RUNBOOK.md` for repeatable personal/business statement validation and failure capture.
