# Secure Data Fetcher - Logging Strategy (MVP)

Last updated: 2026-02-17
References:
- `docs/PRODUCT.md`
- `docs/IMPLEMENTATION_PLAN.md`
- `docs/TEST_PLAN.md`
- `SECURE_DATA_FETCHER_MVP_TECH_SPEC_V1_1.md`

## 1) Goals

- Make debugging request lifecycles fast and reliable.
- Keep logs queryable and low-noise.
- Prevent sensitive-data leakage by default.
- Support both operational debugging and product analytics from the same events.

## 2) Core Model: Canonical Transition Events

Use structured JSON events with stable schemas.

Because this system is asynchronous across broker + iPhone + iCloud, use canonical transition events (not unstructured line logs).

MVP canonical events:

- `request_created`
- `request_presented_to_phone`
- `request_approved`
- `request_denied`
- `request_expired`
- `execution_started`
- `execution_failed`
- `artifact_written_phone`
- `manifest_verified_broker`
- `request_completed`

## 3) Required Event Fields

Every event MUST include:

- `timestamp`
- `event_name`
- `severity`
- `service` (`broker` or `iphone`)
- `environment` (`dev`, `test`, `prod`)
- `request_id`
- `correlation_id` (same value across related events)
- `duration_ms` (when applicable)

State transition events MUST include:

- `status_before`
- `status_after`

Recommended context fields:

- `agent_request_id`
- `bank_id`
- `period_month`
- `period_year`
- `error_code`
- `retriable` (boolean)
- `source` (`BROKER`, `PHONE`, `BANK`, `ICLOUD`)
- `stage` (`APPROVAL`, `AUTH`, `NAVIGATION`, `DOWNLOAD`, `INGEST`, `VERIFY`)

## 4) Correlation Rules

- `request_id` is the primary join key across all logs.
- `agent_request_id` is a secondary join key when present.
- iPhone and broker events for the same flow MUST share the same `request_id`.

## 5) Redaction and Safety Rules

Never log:

- bank username/password
- keychain secrets
- shared HMAC secrets
- API tokens
- authorization headers
- session cookies
- raw statement contents
- raw bank HTML

Allowed metadata:

- request id
- month/year
- sanitized error details
- file byte size
- file SHA-256

## 6) Event Example

```json
{
  "timestamp": "2026-02-17T20:11:42.213Z",
  "event_name": "execution_failed",
  "severity": "WARN",
  "service": "iphone",
  "environment": "dev",
  "request_id": "0f2d4c3e-8a6f-4a9d-a1f8-5f2f7f9d1c04",
  "correlation_id": "0f2d4c3e-8a6f-4a9d-a1f8-5f2f7f9d1c04",
  "status_before": "EXECUTING",
  "status_after": "FAILED",
  "duration_ms": 61102,
  "error_code": "BANK_2FA_TIMEOUT",
  "source": "BANK",
  "stage": "AUTH",
  "retriable": true
}
```

## 7) Sampling Policy (MVP)

- Keep 100% of failures and security-significant outcomes:
- denied
- expired
- execution failed
- manifest verification failed
- Keep 100% of all requests for first 30 days of MVP.
- Optionally downsample successful completions later.

## 8) Severity Policy

- `ERROR`: invariant breach, verification failure, internal fault
- `WARN`: expected but important failure path (deny, timeout, retriable exec errors)
- `INFO`: major lifecycle transitions and terminal outcomes
- `DEBUG`: local diagnostics only; disabled outside dev

## 9) Implementation Requirements

Broker:

- central logger wrapper with schema validation
- central state transition function emits transition events
- no raw `console.log` in security-sensitive modules

iPhone:

- local audit log mirrors canonical event names where possible
- sanitize and bound error details
- avoid high-volume noisy logs; emit milestone events

## 10) Query Patterns To Support

- failures by `error_code` in last 24h
- requests stuck in non-terminal status for >10m
- full event chain by `request_id`
- manifest verification failures grouped by reason

## 11) Logging Test Requirements

- schema validation tests for canonical events
- redaction tests for forbidden keys/patterns
- transition emission tests (one event per transition)
- correlation tests (`request_id` present in all lifecycle events)

## 12) Rollout Plan

1. Implement broker logger wrapper and event schema.
2. Emit canonical events from broker state transitions.
3. Mirror equivalent event names in iPhone audit logging.
4. Add redaction and schema tests.
5. Review first-week logs and trim noisy fields.
