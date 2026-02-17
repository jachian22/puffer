# Secure Data Fetcher - MVP Implementation Plan

Last updated: 2026-02-17
References:
- `SECURE_DATA_FETCHER_MVP_TECH_SPEC_V1_1.md`
- `docs/PRODUCT.md`
- `docs/LOGGING_STRATEGY.md`

## 1) Implementation Goals

Build a secure, end-to-end MVP that is:

- usable by a single user on one iPhone + one computer
- strict about credential isolation and request integrity
- observable via clear statuses and logs

## 2) Technical Stack

Broker:

- Runtime: Bun + TypeScript
- HTTP: Hono (or equivalent lightweight framework)
- DB: SQLite
- Telegram: Bot API via long polling
- File ingestion: Node fs watcher + reconciliation scan
- Crypto: HMAC-SHA256 + SHA-256

iPhone app:

- Swift (iOS 16+)
- LocalAuthentication (Face ID)
- Keychain Services
- WKWebView with non-persistent store
- FileManager + iCloud container APIs

## 3) Suggested Repository Layout

- `docs/`
- `broker/src/server.ts`
- `broker/src/env.ts`
- `broker/src/db/`
- `broker/src/crypto/`
- `broker/src/telegram/`
- `broker/src/requests/`
- `broker/src/icloud/`
- `broker/src/api/agent.ts`
- `broker/src/api/phone.ts`
- `broker/src/tests/`
- `ios/SecureDataFetcher/`
- `ios/SecureDataFetcherTests/`

## 4) Milestone Plan

## Milestone 0 - Project Scaffolding

Deliver:

- broker scaffold, config loader, health endpoint
- iOS app scaffold with tabs/screens for setup + requests + logs
- shared constants for statuses/error codes
- logging schema scaffold aligned to `docs/LOGGING_STRATEGY.md`

Exit criteria:

- broker starts and responds to health check
- iOS app builds and runs on target device

## Milestone 1 - Broker Data Model + Migrations

Deliver:

- SQLite migrations for `pending_requests`, `completion_manifests`, and supporting indexes
- conditional state transition queries (atomic)
- replay fields (`nonce`, `completion_nonce`) with uniqueness constraints

Exit criteria:

- migrations apply cleanly on fresh DB
- invalid transition attempts are rejected by tests

## Milestone 2 - Auth and API Baseline

Deliver:

- agent auth middleware (`BROKER_API_TOKEN`)
- phone auth middleware (`PHONE_API_TOKEN`)
- request size limits and baseline rate limiting
- loopback bind default (`BROKER_HOST=127.0.0.1`)

Exit criteria:

- unauthorized calls return 401
- oversize payloads rejected
- rate-limited paths return 429

## Milestone 3 - Signed Envelope Protocol

Deliver:

- canonical JSON serialization routine
- request envelope signer/verifier (HMAC-SHA256)
- nonce generation and uniqueness checks
- `POST /request` and `GET /phone/requests/pending`

Exit criteria:

- envelope signature verification succeeds for valid payloads
- tampered payload/signature rejected
- duplicate nonce insertion fails

## Milestone 4 - iPhone Intake + Approval UX

Deliver:

- phone pull client for pending envelopes
- signature/expiry/replay validation before rendering
- approval screen with countdown
- Face ID gated approve/deny actions
- decision callback API integration

Exit criteria:

- approval cannot occur without successful biometric auth
- deny and approve produce correct broker state transitions
- expired request cannot be approved

## Milestone 5 - Credential Setup and Secure Storage

Deliver:

- onboarding flow for bank credentials
- Keychain read/write wrappers with biometric access control
- local credential health checks and error states

Exit criteria:

- credentials are retrievable only under biometric gate
- credentials absent from app logs and local DB rows

## Milestone 6 - Bank Automation Engine

Deliver:

- WKWebView execution engine with non-persistent data store
- hardcoded bank navigation script
- month/year selection and PDF capture
- timeout handling and normalized execution errors

Exit criteria:

- happy path produces PDF bytes
- known failures map to required error codes

## Milestone 7 - Signed Manifest + iCloud Write Path

Deliver:

- phone-side PDF hash computation
- signed completion manifest generation
- temp-file then atomic rename protocol for PDF + manifest
- iCloud write retries and failure reporting

Exit criteria:

- valid PDF + manifest appear in iCloud inbox
- manifest signature and hash match expected values

## Milestone 8 - Broker Ingestion and Verification

Deliver:

- iCloud path normalization
- best-effort `fs.watch` listener
- startup reconciliation scan and periodic reconcile loop
- file stability checks
- manifest verification and terminal state updates

Exit criteria:

- completion processed even when watch event is missed
- hash mismatch or bad signature never marks `COMPLETED`

## Milestone 9 - Telegram Nudge Integration

Deliver:

- pending request nudge message
- optional completion info message
- messaging retries and safe failure handling

Exit criteria:

- request pipeline works if Telegram send fails (non-blocking)
- Telegram content is never used as authoritative protocol input

## Milestone 10 - End-to-End Hardening and Test Matrix

Logging deliverables for this milestone:

- canonical transition event emission across broker and phone
- redaction enforcement in logger wrapper
- log schema and correlation tests integrated in CI

Deliver:

- integration tests for full request lifecycle
- security tests (tamper/replay/signature mismatch)
- reliability tests (restart, delayed sync, missed watch event)
- operational runbook for setup and debugging

Exit criteria:

- all must-pass MVP tests green
- no critical security findings open

## 5) Testing Strategy

Unit tests:

- signature canonicalization and verification
- state transition guards
- nonce replay checks
- hash verification

Integration tests:

- agent request -> phone approval -> iCloud completion -> broker terminal status
- fail paths for deny, expiry, execution timeout, malformed manifest

Manual tests:

- first-run onboarding on physical device
- Face ID failure/retry behavior
- bank 2FA interruption path

## 6) Operational Considerations

- Log only sanitized metadata, never credentials
- Correlate logs by `request_id`
- Add startup self-check for:
- required env vars present
- iCloud inbox path exists and is writable
- DB migration state current

## 7) Dependencies and Sequencing

Critical path:

1. broker schema + state machine
2. signed envelopes
3. phone pull + approval UX
4. bank automation + manifest writing
5. broker ingestion verification

Parallelizable:

- Telegram nudge integration (after broker core exists)
- runbook docs and operational scripts

## 8) Delivery Risks

- Bank site variability in WKWebView
- iCloud sync behavior variability across network conditions
- iOS biometric/keychain edge cases on device upgrades

Mitigations:

- strict error coding
- reconciliation loops and retries
- staged rollout with real-device validation gates

## 9) Definition of Done (MVP)

MVP is done when:

- user can submit and approve a statement request end-to-end
- broker returns deterministic terminal status
- all security invariants from spec are enforced in code
- mandatory tests pass consistently on CI/local runs
