# Secure Data Fetcher - Test Plan (MVP v1.1)

Last updated: 2026-02-17
References:
- `SECURE_DATA_FETCHER_MVP_TECH_SPEC_V1_1.md`
- `docs/PRODUCT.md`
- `docs/IMPLEMENTATION_PLAN.md`
- `docs/LOGGING_STRATEGY.md`

## 1) Purpose

Define the minimum test bar for declaring MVP work complete and releasable.

This plan is structured for:

- fast local feedback
- deterministic CI gating
- explicit security regression coverage

## 2) Test Pyramid and Priorities

Priority levels:

- `P0`: release-blocking, must pass on every PR
- `P1`: required before release branch cut
- `P2`: non-blocking quality and observability tests

Test layers:

- Unit tests (deterministic logic, no network, no filesystem side effects)
- Integration tests (real broker router + SQLite + controlled filesystem)
- End-to-end tests (agent -> broker -> phone simulator/device path)
- Manual/device tests (Face ID and WKWebView bank flow validation)

## 3) Proposed Test Layout

Broker tests:

- `broker/tests/unit/canonicalization.test.ts`
- `broker/tests/unit/request_signature.test.ts`
- `broker/tests/unit/manifest_signature.test.ts`
- `broker/tests/unit/nonce_replay.test.ts`
- `broker/tests/unit/state_machine.test.ts`
- `broker/tests/unit/error_mapping.test.ts`
- `broker/tests/unit/rate_limit.test.ts`
- `broker/tests/integration/agent_api_request.test.ts`
- `broker/tests/integration/phone_pending_requests.test.ts`
- `broker/tests/integration/phone_decision_transitions.test.ts`
- `broker/tests/integration/status_polling.test.ts`
- `broker/tests/integration/auth_middleware.test.ts`
- `broker/tests/integration/icloud_ingest_valid.test.ts`
- `broker/tests/integration/icloud_ingest_invalid_manifest.test.ts`
- `broker/tests/integration/icloud_ingest_hash_mismatch.test.ts`
- `broker/tests/integration/icloud_reconcile_missed_watch.test.ts`
- `broker/tests/integration/concurrency_double_approve.test.ts`
- `broker/tests/integration/concurrency_double_complete.test.ts`
- `broker/tests/security/path_traversal_rejection.test.ts`
- `broker/tests/security/log_redaction.test.ts`

iOS tests:

- `ios/SecureDataFetcherTests/EnvelopeValidationTests.swift`
- `ios/SecureDataFetcherTests/ReplayProtectionTests.swift`
- `ios/SecureDataFetcherTests/ManifestSigningTests.swift`
- `ios/SecureDataFetcherTests/RequestStoreStateMappingTests.swift`
- `ios/SecureDataFetcherTests/KeychainAccessControlTests.swift`
- `ios/SecureDataFetcherTests/WKWebViewSessionPolicyTests.swift`
- `ios/SecureDataFetcherTests/ExecutionErrorMappingTests.swift`
- `ios/SecureDataFetcherUITests/ApprovalFlowUITests.swift`
- `ios/SecureDataFetcherUITests/ExpiredRequestUITests.swift`
- `ios/SecureDataFetcherUITests/DeniedRequestUITests.swift`

End-to-end tests:

- `e2e/request_to_completion.test.ts`
- `e2e/request_denied.test.ts`
- `e2e/request_expired.test.ts`
- `e2e/execution_timeout.test.ts`
- `e2e/tampered_manifest_rejected.test.ts`

## 4) P0 Test Requirements (Release-Blocking)

### 4.1 Crypto and Integrity

- Canonical request serialization is deterministic.
- Signed envelope verification rejects tampered payload.
- Signed completion manifest verification rejects tampered payload.
- Envelope nonce replay is rejected.
- Completion nonce replay is rejected.

### 4.2 State Machine

- Only allowed transitions succeed.
- Terminal states cannot transition back to non-terminal states.
- TTL semantics: unapproved past `approval_expires_at` => `EXPIRED`.
- TTL semantics: approved request exceeding execution timeout => `FAILED` with `EXECUTION_TIMEOUT`.

### 4.3 Broker API + Auth

- `POST /request` creates valid signed envelope and pending state.
- `GET /phone/requests/pending` returns only pending, non-terminal requests.
- `POST /phone/requests/:id/decision` enforces state and TTL.
- `GET /request/:id` returns expected status and HTTP code mapping.
- Missing/invalid `BROKER_API_TOKEN` returns `401`.
- Missing/invalid `PHONE_API_TOKEN` returns `401`.

### 4.4 iCloud Ingestion and Completion Validation

- Valid PDF + valid manifest => `COMPLETED`.
- Manifest signature mismatch => never `COMPLETED`.
- PDF digest mismatch => never `COMPLETED`.
- Missed watcher event recovered by reconciliation loop.
- Partial/unstable file is not processed until stable.

### 4.5 Concurrency and Idempotence

- Concurrent approvals: only one state transition wins.
- Concurrent completion processing: only one terminal update accepted.
- Retried identical decision calls are idempotent and safe.

### 4.6 iOS Security

- Invalid/expired/replayed envelope never reaches approval action state.
- Biometric approval is required for `APPROVE`.
- Credentials are absent from app DB records and logs.
- WKWebView is configured as non-persistent.

### 4.7 Logging Safety and Correlation

- Canonical log schema validation tests pass.
- Redaction tests prove secrets/tokens/credentials are never serialized.
- Lifecycle logs always include `request_id`.
- Transition events are emitted exactly once per successful state transition.

## 5) P1 Test Requirements (Pre-Release Branch)

- Bank automation happy path on real device for target bank.
- Bank automation failure mode mapping includes `BANK_LOGIN_FAILED`.
- Bank automation failure mode mapping includes `BANK_2FA_TIMEOUT`.
- Bank automation failure mode mapping includes `NAVIGATION_FAILED`.
- Bank automation failure mode mapping includes `PDF_DOWNLOAD_FAILED`.
- Bank automation failure mode mapping includes `ICLOUD_WRITE_FAILED`.
- End-to-end latency SLO sanity test under nominal network.
- Startup/restart recovery test for broker preserving in-flight requests.

## 6) P2 Test Requirements (Quality/Operational)

- Structured audit log schema validation.
- Rate-limit boundary behavior under burst load.
- Long-duration soak test for reconciliation loop.
- Developer ergonomics tests for local setup scripts.

## 7) CI Pipeline Stages

Recommended CI stages:

1. `lint-and-typecheck`
- broker lint + typecheck.
- iOS static checks.

2. `unit-p0`
- run all P0 unit tests (broker + iOS unit).

3. `integration-p0`
- run broker integration/security/concurrency P0 suites against ephemeral SQLite and temp iCloud directory.

4. `e2e-p0`
- run core end-to-end scenarios with controlled stubs.

5. `ios-ui-smoke` (required on release branch; optional on PR)
- run minimal UI tests for approval and denial flows.

6. `p1-full` (release branch only)
- run all P1 tests including real-device/manual-assisted bank validation checklist.

## 8) Definition of Done Gates

A feature/change is Done only if:

1. Relevant new logic includes tests at the right layer.
2. No existing P0 test is weakened or skipped.
3. All CI P0 stages pass.
4. Security-sensitive changes include at least one regression test.
5. Status transitions and error codes are validated by tests.

MVP Release Done only if:

1. Full P0 + P1 suites pass.
2. Manual device checklist passes for Face ID + bank flow.
3. No open critical/high severity defects in security or state correctness.

## 9) Manual Device Checklist (Release)

- Approve request with Face ID successfully executes.
- Deny request results in `DENIED`.
- Let request expire results in `EXPIRED`.
- Force execution timeout results in `FAILED/EXECUTION_TIMEOUT`.
- Kill/restart broker during in-flight request, verify eventual consistency.
- Confirm no credentials in broker logs or files.

## 10) Test Data and Environment Rules

- Never use real banking credentials in automated tests.
- Use synthetic PDFs and deterministic fixtures for digest tests.
- Keep secrets in CI via secure env vars only.
- Isolate filesystem tests to temp directories.
- Reset DB state between tests to avoid cross-test coupling.

## 11) Coverage Guidance

Coverage thresholds (guidance, not sole quality signal):

- broker unit tests: 90%+ statements for crypto/state modules
- broker integration critical paths: 85%+ statements
- iOS core security modules: 90%+ statements where measurable

Hard rule:

- A coverage increase does not substitute for missing P0 scenario coverage.

## 12) Ownership

Primary owners:

- Broker engineering: broker unit/integration/security/e2e suites
- iOS engineering: iOS unit/UI suites and manual device validation

Review requirement:

- At least one reviewer must confirm P0 test impact for security-sensitive PRs.
