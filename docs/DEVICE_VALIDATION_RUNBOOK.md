# Device Validation Runbook (Chase)

Last updated: 2026-02-17

## Goal

Validate end-to-end execution on a real iPhone + real Chase session, and capture actionable diagnostics when any step fails.

## Prerequisites

- Broker is running on macOS with valid env vars.
- iPhone app is running in `Live` mode with:
  - broker base URL
  - phone API token
  - broker shared secret
  - local iCloud inbox path
- At least one credential saved for bank ID `default`.
- iPhone can sign in to Chase manually in normal Safari (sanity check).

## Test Matrix

Run each scenario once:

1. Personal checking statement (known month/year with available PDF)
2. Personal credit card statement (known month/year with available PDF)
3. Business account statement (known month/year with available PDF)
4. Expired request path (let approval TTL lapse)
5. Deny path (explicit deny in app)

## Per-Run Steps (5-7 minutes)

1. Create request from broker/agent for specific month/year.
2. Open iPhone app and tap `Approve + Execute`.
3. In `Execution Browser`, watch `Diagnostics` panel in real time.
4. If challenge appears:
   - complete challenge in webview
   - tap `Continue`
5. Confirm terminal outcome:
   - success: PDF + manifest in iCloud inbox, broker status `COMPLETED`
   - failure: broker status `FAILED`, capture diagnostics snapshot

## Capture Checklist (for every run)

- Request ID
- Statement type/account surface (personal checking / personal card / business)
- Month/year
- Final status (`COMPLETED`, `FAILED`, `DENIED`, `EXPIRED`)
- First failing stage (if failed)
- Last 10 diagnostics lines from app
- Any visible Chase page text around failure point

## Common Failure Mapping

- `BANK_LOGIN_FAILED`:
  - likely login selector or redirect variant issue
  - capture diagnostics line around "Credential injection" and "Waiting for login"
- `NAVIGATION_FAILED`:
  - likely statement-selection mismatch
  - capture diagnostics line containing "Statement selection did not match..." with `topCandidates`
- `PDF_DOWNLOAD_FAILED`:
  - likely download control mismatch or response variant
  - capture diagnostics line containing "Download trigger script returned false" with `topCandidates`
- `BANK_2FA_TIMEOUT`:
  - challenge not resolved before timeout
  - note challenge type shown by app (`SMS code`, `Authenticator app`, `Captcha`, etc.)

## Definition of Done Gate for Device Pass

Minimum acceptance before tightening for TestFlight:

1. 3 consecutive successful runs spanning personal + business surfaces.
2. No unexplained `NAVIGATION_FAILED` or `PDF_DOWNLOAD_FAILED` on repeated identical input.
3. Every failed run has enough diagnostics to identify next selector/action update in one iteration.

## Report Template

Use this exact template for each run:

```
request_id:
account_surface:
period:
result:
error_code:
first_failing_stage:
last_10_diagnostics:
notes:
```
