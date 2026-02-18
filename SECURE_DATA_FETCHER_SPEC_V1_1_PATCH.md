# Secure Data Fetcher - MVP Technical Specification v1.1 Patch

Last updated: 2026-02-17
Applies to: MVP spec draft (2026-02-17)
Status: Proposed normative patch

## Purpose

This patch resolves the following design gaps before implementation:

- Request authenticity and replay protection
- iOS delivery path ambiguity
- Completion spoofing risk
- Cross-component state mismatch
- Fragile iCloud file detection
- Ambiguous timeout semantics
- Missing broker API authentication baseline
- Security wording precision

## Normative Changes

### 1) Signed request envelope and replay protection

All broker-to-phone fetch requests MUST use a signed envelope.

Envelope schema:

```json
{
  "version": "1",
  "request_id": "0f2d4c3e-8a6f-4a9d-a1f8-5f2f7f9d1c04",
  "type": "statement",
  "bank_id": "default",
  "params": { "month": 1, "year": 2026 },
  "issued_at": "2026-02-17T19:00:00.000Z",
  "approval_expires_at": "2026-02-17T19:05:00.000Z",
  "nonce": "1e0f14ef6f2d44f6a65b2e4b7f0bc0be",
  "signature": "base64url(hmac_sha256(shared_secret, canonical_payload_bytes))"
}
```

Canonical payload:

- JSON object with keys in lexicographic order.
- UTF-8 bytes.
- No insignificant whitespace.
- `signature` field excluded from the signed bytes.

Validation rules on phone:

- MUST verify signature before showing approval UI.
- MUST reject envelopes with unknown `version`.
- MUST reject if `approval_expires_at` is in the past.
- MUST reject if `nonce` was previously seen.
- MUST persist accepted nonce and request_id for at least 24 hours.

Validation rules on broker:

- MUST never reuse a nonce.
- MUST enforce uniqueness for `(request_id)` and `(nonce)`.

Recommended DB additions:

- iPhone `requests`: `signature_valid` (bool), `nonce` (unique), `envelope_json`.
- Broker `pending_requests`: `nonce` (unique), `signed_envelope_json`.

### 2) iPhone delivery path (explicit MVP mode)

MVP delivery mode is defined as:

- Telegram push notifies user that a request is pending.
- User opens Secure Data Fetcher app manually.
- App (foreground only) fetches pending signed envelopes from broker.
- App does NOT rely on background Telegram bot processing.

Broker API for phone:

- `GET /phone/requests/pending`
- Auth: `Authorization: Bearer <PHONE_SHARED_TOKEN>`
- Returns signed envelopes only.

Phone fetch behavior:

- Poll on app foreground/resume and via manual refresh.
- Display only signature-validated, non-expired, non-replayed requests.

### 3) Signed completion manifest and file integrity

Completion is authoritative only when both file and signed manifest verify.

Phone MUST produce:

- PDF file in iCloud inbox.
- JSON manifest in same folder with `.manifest.json` suffix.

Manifest schema:

```json
{
  "version": "1",
  "request_id": "0f2d4c3e-8a6f-4a9d-a1f8-5f2f7f9d1c04",
  "filename": "0f2d4c3e-8a6f-4a9d-a1f8-5f2f7f9d1c04-jan-2026.pdf",
  "sha256": "hex_of_pdf_bytes",
  "bytes": 248193,
  "completed_at": "2026-02-17T19:03:42.000Z",
  "nonce": "completion_nonce_unique",
  "signature": "base64url(hmac_sha256(shared_secret, canonical_manifest_payload))"
}
```

Broker acceptance rules:

- MUST verify manifest signature.
- MUST ensure `request_id` exists and is executable.
- MUST verify referenced PDF exists and SHA-256 matches manifest.
- MUST reject duplicate completion nonce.
- MUST transition to `COMPLETED` only after all checks pass.

Telegram completion text is advisory only and MUST NOT change request status.

### 4) Canonical state machine alignment

Broker canonical states:

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
- `EXECUTING -> COMPLETED`
- `EXECUTING -> FAILED`
- `APPROVED -> FAILED` (execution initialization failure)

Disallowed transitions:

- Any transition from terminal states (`COMPLETED`, `FAILED`, `DENIED`, `EXPIRED`) to non-terminal states.
- `EXPIRED -> APPROVED`.

Broker API MUST return status values from this exact enum only.
iPhone state names MAY differ internally but MUST map losslessly to broker states.

### 5) iCloud ingestion hardening

`fs.watch` MAY be used but MUST NOT be the sole source of truth.

Broker ingestion requirements:

- Startup reconciliation scan of inbox and manifests.
- Periodic reconciliation every 10 seconds.
- File stability check before hashing:
- size unchanged across two checks at least 2 seconds apart.
- mtime unchanged across the same checks.
- Ignore temporary filenames ending in `.tmp`.

Phone write protocol:

- Write PDF to temp file.
- fsync/close.
- Atomic rename temp file to final `.pdf`.
- Write manifest to temp file.
- Atomic rename to final `.manifest.json`.

Filename rules:

- Final PDF name: `{request_id}-{month_abbrev}-{year}.pdf`
- Final manifest name: `{request_id}-{month_abbrev}-{year}.manifest.json`

### 6) Timeout semantics (split approval vs execution)

Define two independent timers:

- `approval_ttl`: 5 minutes from broker request creation.
- `execution_timeout`: 10 minutes from execution start on phone.

Semantics:

- `EXPIRED` means not approved before `approval_expires_at`.
- Once approved within TTL, request MUST NOT become `EXPIRED`.
- Runtime failures after approval map to `FAILED` with specific error codes.

Required error codes:

- `APPROVAL_EXPIRED`
- `DENIED_BY_USER`
- `EXECUTION_TIMEOUT`
- `BANK_LOGIN_FAILED`
- `BANK_2FA_TIMEOUT`
- `NAVIGATION_FAILED`
- `PDF_DOWNLOAD_FAILED`
- `ICLOUD_WRITE_FAILED`
- `MANIFEST_VERIFICATION_FAILED`

### 7) Broker API authentication baseline

All agent-facing broker endpoints MUST require broker auth.

MVP requirements:

- Static high-entropy bearer token in `BROKER_API_TOKEN`.
- Reject missing/invalid token with 401.
- Bind server to `127.0.0.1` by default.
- If bound externally, TLS termination is REQUIRED.
- Request body size cap 256 KiB.
- Rate limit minimum:
- per-token: 60 requests/minute.
- global: 300 requests/minute.

### 8) Security wording updates

Replace:

- "credentials never transmitted over network"

With:

- "Credentials are never transmitted to broker, Telegram, iCloud, or agent. Credentials are sent only from iPhone to bank endpoints over TLS during login."

Add:

- "iCloud provides Apple-managed encryption in transit and at rest. This channel is not end-to-end encrypted for this application protocol."

## API Additions and Updates

### New broker endpoint for phone pull

`GET /phone/requests/pending`

Response:

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

### Updated broker status endpoint

`GET /request/:request_id` returns:

- `202` for `SENT|PENDING_APPROVAL|APPROVED|EXECUTING`
- `200` for `COMPLETED|FAILED|DENIED|EXPIRED`

Example terminal responses:

```json
{ "request_id": "uuid", "status": "COMPLETED", "file_path": "/path/file.pdf", "completed_at": "ISO8601" }
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

## Database Patch (MVP delta)

Broker `pending_requests` add:

- `nonce` TEXT UNIQUE NOT NULL
- `approval_expires_at` TEXT NOT NULL
- `execution_started_at` TEXT NULL
- `execution_timeout_at` TEXT NULL
- `error_code` TEXT NULL
- `completion_nonce` TEXT UNIQUE NULL
- `result_sha256` TEXT NULL

Broker new table `completion_manifests`:

- `request_id` PK/FK
- `filename`
- `sha256`
- `bytes`
- `completed_at`
- `nonce` UNIQUE
- `signature`
- `manifest_json`
- `verified_at`

iPhone `requests` add:

- `nonce` TEXT UNIQUE NOT NULL
- `signature` TEXT NOT NULL
- `signature_valid` INTEGER NOT NULL DEFAULT 0
- `envelope_json` TEXT NOT NULL

## Acceptance Criteria Additions

Add required tests:

- Tampered signed request is rejected on phone.
- Replayed request nonce is rejected on phone.
- Tampered manifest signature is rejected by broker.
- Manifest/PDF hash mismatch does not mark request complete.
- Lost `fs.watch` event still completes via reconciliation loop.
- Approval after TTL returns `EXPIRED`.
- Approved-in-time request exceeding execution timeout returns `FAILED` with `EXECUTION_TIMEOUT`.
- Unauthenticated broker API request returns 401.

## Migration and Rollout Notes

- `version` field in envelope and manifest is mandatory for forward compatibility.
- During rollout, broker MAY support unsigned legacy flow behind a temporary flag.
- Legacy unsigned mode MUST be removed before production use.
