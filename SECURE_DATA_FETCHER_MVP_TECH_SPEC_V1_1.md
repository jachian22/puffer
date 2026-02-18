# Secure Data Fetcher - MVP Technical Specification v1.1

Last updated: 2026-02-17
Status: Finalized MVP spec

## 1) Overview

Secure Data Fetcher is a human-approved, phone-executed system for retrieving personal bank statements.

Design intent:

- Credentials live only on iPhone.
- Every fetch requires explicit Face ID approval.
- Execution happens only on iPhone.
- Computer broker coordinates requests and completion tracking.
- Returned data flows through iCloud Drive inbox.

In MVP, the system supports one hardcoded bank and statement PDF retrieval only.

## 2) MVP Goals

- iPhone app:
- one-time credential setup in Keychain
- Face ID approval per request
- foreground-only browser automation via WKWebView
- saving output files to iCloud Drive
- local audit logging
- Broker:
- request intake from agent
- signed request envelope creation
- Telegram notification as a user nudge
- iCloud inbox ingestion and request matching
- status API for agent polling
- Integrity:
- request shown to user is exactly what can execute
- replay attempts are rejected
- completion is accepted only after signature and hash verification
- Security:
- credentials never exist on broker/agent
- credentials never appear in logs
- credentials are only sent from iPhone directly to bank endpoints over TLS

## 3) Non-Goals (MVP)

- Multiple banks
- Write operations
- Transaction JSON extraction
- Pre-approval policies
- Background execution on iPhone
- Multiple return channels
- Web dashboard
- Credential sync/backup/export

## 4) Locked Decisions

- iPhone app: Swift, iOS 16+
- Browser automation: WKWebView, non-persistent data store
- Credential storage: iOS Keychain + access control with biometrics
- Authentication for approval: Face ID only (no passcode fallback in MVP)
- Broker runtime: TypeScript on Bun
- Telegram integration: bot + long polling
- Return path: iCloud Drive inbox folder
- Request body: not supported (GET-equivalent navigation only)
- Single bank script: hardcoded selectors/navigation
- Approval TTL: 5 minutes
- Execution timeout: 10 minutes

## 5) Architecture

### 5.1 Components

1. iPhone app
- Credential manager
- Request inbox sync client (broker pull API, foreground)
- Approval UI + Face ID gate
- WKWebView automation engine
- iCloud writer (PDF + manifest)
- Local audit log

2. Computer broker
- Agent API
- Phone API
- Telegram notifier
- iCloud watcher + reconciliation loop
- Request tracker/state machine

### 5.2 Deployment Assumption

- iPhone app runs on user’s personal iPhone.
- Broker runs on user’s computer near the agent process.
- Broker defaults to loopback binding (`127.0.0.1`).

## 6) Trust Boundaries

- Trusted execution boundary: iPhone app + iOS secure storage.
- Untrusted transport: Telegram messages.
- Semi-trusted sync channel: iCloud Drive (Apple-managed encryption in transit/at rest, not app-level E2EE protocol).
- Broker is trusted for orchestration and signature verification, but does not hold bank credentials.

## 7) Cryptographic Protocols

### 7.1 Shared Material

- `BROKER_PHONE_SHARED_SECRET`: HMAC signing key shared by broker and phone.
- `PHONE_API_TOKEN`: bearer token for phone-authenticated broker endpoints.
- `BROKER_API_TOKEN`: bearer token for agent-authenticated broker endpoints.

### 7.2 Signed Request Envelope

Every broker-created request MUST be a signed envelope.

```json
{
  "version": "1",
  "request_id": "uuid",
  "type": "statement",
  "bank_id": "default",
  "params": { "month": 1, "year": 2026 },
  "issued_at": "ISO8601",
  "approval_expires_at": "ISO8601",
  "nonce": "hex_32",
  "signature": "base64url(hmac_sha256(secret, canonical_payload))"
}
```

Signing rules:

- Canonical JSON with lexicographically sorted keys.
- UTF-8 encoded bytes.
- `signature` excluded from signed payload.

Phone validation rules:

- verify signature before display
- reject unknown version
- reject expired envelope
- reject replayed nonce
- persist accepted nonce and request_id for minimum 24h

Broker rules:

- `request_id` unique
- request nonce unique

### 7.3 Signed Completion Manifest

Phone writes a manifest next to each PDF.

```json
{
  "version": "1",
  "request_id": "uuid",
  "filename": "uuid-jan-2026.pdf",
  "sha256": "hex",
  "bytes": 248193,
  "completed_at": "ISO8601",
  "nonce": "hex_32",
  "signature": "base64url(hmac_sha256(secret, canonical_payload))"
}
```

Broker acceptance:

- verify manifest signature
- verify request exists and is executable
- verify PDF exists and SHA-256 matches
- reject duplicate completion nonce
- transition to `COMPLETED` only after all checks pass

Telegram completion text is informational only.

## 8) Canonical State Machine

Broker states:

- `SENT`
- `PENDING_APPROVAL`
- `APPROVED`
- `EXECUTING`
- `COMPLETED`
- `FAILED`
- `DENIED`
- `EXPIRED`

Allowed transitions:

- `SENT -> PENDING_APPROVAL`
- `PENDING_APPROVAL -> APPROVED`
- `PENDING_APPROVAL -> DENIED`
- `PENDING_APPROVAL -> EXPIRED`
- `APPROVED -> EXECUTING`
- `APPROVED -> FAILED`
- `EXECUTING -> COMPLETED`
- `EXECUTING -> FAILED`

Terminal states:

- `COMPLETED`, `FAILED`, `DENIED`, `EXPIRED`

Disallowed:

- Any terminal-to-non-terminal transition
- `EXPIRED -> APPROVED`

Timeout semantics:

- `EXPIRED` means approval was not granted within approval TTL.
- After timely approval, timeout failures are `FAILED` (`EXECUTION_TIMEOUT`), not `EXPIRED`.

## 9) Data Model

### 9.1 iPhone App (Core Data/SQLite)

### `credentials`

- `id` (PK)
- `bank_id` (string, default `default`)
- `username_keychain_ref`
- `password_keychain_ref`
- `created_at`
- `updated_at`
- `last_used_at` (nullable)

### `requests`

- `id` (PK, UUID)
- `nonce` (unique)
- `signature` (string)
- `signature_valid` (bool)
- `envelope_json` (text)
- `bank_id` (string)
- `request_type` (`statement`)
- `parameters_json` (`month`, `year`)
- `status` (`PENDING_APPROVAL|APPROVED|EXECUTING|COMPLETED|FAILED|DENIED|EXPIRED`)
- `created_at`
- `updated_at`
- `approved_at` (nullable)
- `completed_at` (nullable)
- `error_code` (nullable)
- `error_message` (nullable)
- `result_filename` (nullable)

### `audit_log`

- `id` (PK)
- `created_at`
- `request_id` (nullable)
- `event_type`
- `event_details_json` (sanitized metadata)

### 9.2 Broker (SQLite)

### `pending_requests`

- `id` (PK, UUID)
- `agent_request_id` (nullable)
- `request_type` (`statement`)
- `parameters_json`
- `nonce` (unique)
- `signed_envelope_json`
- `status` (`SENT|PENDING_APPROVAL|APPROVED|EXECUTING|COMPLETED|FAILED|DENIED|EXPIRED`)
- `created_at`
- `updated_at`
- `approval_expires_at`
- `execution_started_at` (nullable)
- `execution_timeout_at` (nullable)
- `telegram_message_id` (nullable)
- `result_file_path` (nullable)
- `result_sha256` (nullable)
- `error_code` (nullable)
- `error_message` (nullable)
- `completion_nonce` (unique, nullable)

### `completion_manifests`

- `request_id` (PK/FK)
- `filename`
- `sha256`
- `bytes`
- `completed_at`
- `nonce` (unique)
- `signature`
- `manifest_json`
- `verified_at`

## 10) APIs

All JSON requests/responses use UTF-8.

### 10.1 Agent-facing Broker API

Auth:

- `Authorization: Bearer <BROKER_API_TOKEN>`

### `POST /request`

Input:

```json
{
  "type": "statement",
  "month": 1,
  "year": 2026,
  "agent_request_id": "optional"
}
```

Behavior:

- validate input
- create request_id + nonce
- build signed envelope
- insert request as `SENT`, then `PENDING_APPROVAL`
- send Telegram notification to user
- return immediately

Response `202`:

```json
{
  "request_id": "uuid",
  "status": "PENDING_APPROVAL",
  "created_at": "ISO8601",
  "approval_expires_at": "ISO8601"
}
```

### `GET /request/:request_id`

Response:

- `202` for `SENT|PENDING_APPROVAL|APPROVED|EXECUTING`
- `200` for terminal statuses
- `404` if unknown request

Terminal examples:

```json
{ "request_id": "uuid", "status": "COMPLETED", "file_path": "/abs/path/file.pdf", "completed_at": "ISO8601" }
```

```json
{ "request_id": "uuid", "status": "FAILED", "error_code": "NAVIGATION_FAILED", "error_message": "selector not found" }
```

```json
{ "request_id": "uuid", "status": "DENIED" }
```

```json
{ "request_id": "uuid", "status": "EXPIRED", "error_code": "APPROVAL_EXPIRED" }
```

### `GET /requests`

List recent requests with status/timestamps.

### 10.2 Phone-facing Broker API

Auth:

- `Authorization: Bearer <PHONE_API_TOKEN>`

### `GET /phone/requests/pending`

Returns signature-bearing envelopes to review.

```json
{
  "requests": [
    {
      "envelope": {
        "version": "1",
        "request_id": "uuid",
        "type": "statement",
        "bank_id": "default",
        "params": { "month": 1, "year": 2026 },
        "issued_at": "ISO8601",
        "approval_expires_at": "ISO8601",
        "nonce": "hex",
        "signature": "base64url"
      }
    }
  ]
}
```

### `POST /phone/requests/:request_id/decision`

Input:

```json
{
  "decision": "APPROVE",
  "decided_at": "ISO8601"
}
```

Rules:

- valid only from `PENDING_APPROVAL`
- approval after TTL rejected, request becomes `EXPIRED`
- `decision=DENY` sets `DENIED`
- `decision=APPROVE` sets `APPROVED`

### `POST /phone/requests/:request_id/failure`

Input:

```json
{
  "error_code": "NAVIGATION_FAILED",
  "error_message": "optional sanitized detail",
  "failed_at": "ISO8601"
}
```

Rules:

- allowed from `APPROVED|EXECUTING`
- transitions to `FAILED`

## 11) Request Flow (Final)

1. Agent submits request to broker (`POST /request`).
2. Broker stores signed envelope and marks request pending.
3. Broker sends Telegram nudge message.
4. User opens iPhone app.
5. iPhone app pulls pending envelopes from broker.
6. App verifies envelope signature/nonce/expiry.
7. App presents approval UI with request details and countdown.
8. User approves with Face ID or denies.
9. App posts decision to broker.
10. On approval, app executes bank flow in foreground WKWebView.
11. App writes PDF + signed manifest to iCloud inbox.
12. Broker detects files, performs stability and signature/hash verification.
13. Broker marks `COMPLETED`.
14. Agent polls and receives completed status and local file path.

## 12) iPhone App Specification

### 12.1 Credential Storage

- Store credentials in Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
- Use `kSecAccessControlBiometryCurrentSet` access control.
- Credentials are non-exportable and non-syncable.

### 12.2 Approval UI Requirements

- bank name
- request type
- target month/year
- truncated request id
- approval TTL countdown
- actions: `Approve with Face ID`, `Deny`

Biometric policy:

- `deviceOwnerAuthenticationWithBiometrics`
- On biometric failure, remain on approval screen.

### 12.3 WKWebView Execution

- `WKWebsiteDataStore.nonPersistent()` required.
- Bank script is hardcoded for one bank.
- Handle optional 2FA with explicit user interaction.
- Capture sanitized debug screenshot only for navigation failures.

### 12.4 iCloud Write Protocol

Folder:

- `iCloud Drive/SecureFetcher/inbox/`

Write order:

1. Write PDF to `.tmp` file
2. Close file
3. Rename to final `.pdf`
4. Write manifest to `.tmp`
5. Rename to final `.manifest.json`

Filename:

- `{request_id}-{month_abbrev}-{year}.pdf`
- `{request_id}-{month_abbrev}-{year}.manifest.json`

## 13) Broker iCloud Ingestion Specification

- Expand and normalize configured iCloud path at startup.
- Use `fs.watch` as best-effort signal only.
- Reconciliation scan on startup.
- Reconciliation loop every 10 seconds.
- File stability check before processing requires unchanged size and mtime across two checks at least 2 seconds apart.
- Ignore temp files.
- On manifest arrival, verify corresponding PDF and digest.

## 14) Telegram Integration Specification

Telegram is not a trusted command channel in MVP.

Broker Telegram message format:

- pending request nudge with request id and period
- optional informational completion message

Telegram content MUST NOT be used as authoritative request payload or completion confirmation.

## 15) Security Requirements

- Never store credentials outside iPhone Keychain.
- Never include credentials/tokens in logs.
- Never trust unsigned request material.
- Never trust unsigned completion claims.
- Enforce all state transitions via conditional DB updates.
- Enforce replay protection with nonce uniqueness.
- Require API auth for both agent and phone endpoints.
- Enforce request size limit (256 KiB minimum requirement).
- Apply per-token and global rate limits.

## 16) Error Handling

Required broker error codes:

- `INVALID_REQUEST_TYPE`
- `MISSING_FIELD`
- `REQUEST_NOT_FOUND`
- `APPROVAL_EXPIRED`
- `DENIED_BY_USER`
- `EXECUTION_TIMEOUT`
- `BANK_LOGIN_FAILED`
- `BANK_2FA_TIMEOUT`
- `NAVIGATION_FAILED`
- `PDF_DOWNLOAD_FAILED`
- `ICLOUD_WRITE_FAILED`
- `MANIFEST_VERIFICATION_FAILED`
- `UNAUTHORIZED`
- `RATE_LIMITED`

HTTP guidance:

- `400` validation failures
- `401` auth failure
- `404` missing request
- `408` approval timeout
- `429` rate limit
- `500` internal errors

## 17) Testing and Verification

Functional tests:

- setup credentials on iPhone
- create request from broker
- receive Telegram nudge
- iPhone fetches pending signed request
- Face ID required to approve
- deny path transitions to `DENIED`
- approved path executes and writes PDF + manifest
- broker verifies and marks `COMPLETED`

Integrity/security tests:

- tampered envelope signature rejected
- replayed request nonce rejected
- tampered manifest signature rejected
- manifest/PDF hash mismatch rejected
- credentials not present on broker filesystem
- credentials not present in logs

Reliability tests:

- missed `fs.watch` event recovered by reconcile loop
- broker restart preserves pending requests
- iCloud sync delays up to 30s handled
- execution timeout transitions to `FAILED` with `EXECUTION_TIMEOUT`

## 18) Configuration

Broker required env:

- `BROKER_API_TOKEN`
- `PHONE_API_TOKEN`
- `BROKER_PHONE_SHARED_SECRET`
- `TELEGRAM_BOT_TOKEN`
- `TELEGRAM_PHONE_CHAT_ID`
- `ICLOUD_INBOX_PATH`
- `BROKER_PORT` (default `8765`)
- `BROKER_HOST` (default `127.0.0.1`)

iPhone onboarding required:

- bank username/password
- broker base URL
- `PHONE_API_TOKEN`
- `BROKER_PHONE_SHARED_SECRET`
- iCloud container identifier

Hardcoded MVP:

- bank login URL
- selectors/navigation script
- approval TTL
- execution timeout

## 19) Post-MVP Roadmap

Phase 2:

- multi-bank support
- configurable bank scripts
- alternate return channels

Phase 3:

- pre-approval policy engine
- batch approvals
- background workflows

Phase 4:

- additional data providers
- Android client
- richer audit export and redaction pipeline
