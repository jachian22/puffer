# Secure Data Fetcher - API Contract Decisions Log

Last updated: 2026-02-17
References:
- `SECURE_DATA_FETCHER_MVP_TECH_SPEC_V1_1.md`
- `docs/IMPLEMENTATION_PLAN.md`
- `docs/TEST_PLAN.md`

Purpose:

- Track API contract decisions for MVP/home usage.
- Preserve explicit upgrade targets for post-MVP scale.

## Decision Log

### 1) Phone endpoint shape

Question:

- Split endpoints (`/decision`, `/failure`) vs unified events endpoint.

MVP/home (locked):

- Use split endpoints:
- `POST /phone/requests/:request_id/decision`
- `POST /phone/requests/:request_id/failure`

Why this is right for MVP debugging:

- Clearer failure localization in low-volume testing.
- Lower schema complexity and faster iteration.

Scale-up target (100+ users):

- Consider migration to unified events endpoint:
- `POST /phone/requests/:request_id/events`

Migration trigger:

- More than two phone-originated lifecycle event types or notable endpoint duplication.

---

### 2) `APPROVED -> EXECUTING` state authority

Question:

- Broker-driven vs phone-driven execution-start transition.

MVP/home (locked):

- Broker-driven transition for simplicity.

Why this is right for MVP debugging:

- One fewer callback path.
- Fewer race conditions while stabilizing core lifecycle.

Known tradeoff:

- May transiently report `EXECUTING` before phone truly starts work.

Scale-up target (100+ users):

- Move to phone-driven execution-start signal for operational accuracy.

Migration trigger:

- Need high-fidelity execution telemetry or recurring "ghost executing" incidents.

---


### 3) Polling response contract for `GET /request/:request_id`

Question:

- Mixed HTTP semantics (`202` pending, `200` terminal) vs always-`200` with status in body.

MVP/home (locked):

- Use mixed semantics:
- `202` for `SENT|PENDING_APPROVAL|APPROVED|EXECUTING`
- `200` for `COMPLETED|FAILED|DENIED|EXPIRED`

Why this is right for MVP debugging:

- Fast manual diagnosis from status code alone.
- Clear lifecycle class distinction in local testing.

Scale-up target (100+ users):

- Re-evaluate based on client ecosystem.
- If non-200 handling causes integration friction, consider always-`200` with strict body schema.

Migration trigger:

- Repeated client bugs caused by `202` handling across SDKs/integrations.

---


### 4) `GET /requests` pagination/filter contract

Question:

- Keep a simple fixed list vs support pagination/filtering now.

MVP/home (locked):

- Implement minimal structured listing now:
- `limit` (default 50, max 200)
- `cursor` (opaque)
- optional `status` filter
- stable sort: newest first

Why this is right for MVP debugging:

- Still simple enough for local use.
- Avoids contract breakage and migration churn shortly after MVP.

Scale-up target (100+ users):

- Extend with additional filters (date range, error code, terminal-only).

Migration trigger:

- Need richer operational dashboards or high request volume histories.

---


### 5) Idempotency semantics

Question:

- Loose best-effort idempotency vs strict deterministic idempotency contract.

MVP/home (locked):

- Use strict idempotency semantics.

Contract details (locked):

- `POST /request`:
- accepts optional `idempotency_key`
- uniqueness scope `(agent_identity, idempotency_key)`
- duplicate returns same `request_id` and current status

- `POST /phone/requests/:id/decision`:
- first valid decision wins
- exact duplicate decision returns idempotent ack with current state
- conflicting decision after terminalization returns explicit `409`

- `POST /phone/requests/:id/failure`:
- terminal requests return idempotent ack (no mutation)
- first eligible failure transitions state
- exact duplicate failure payload returns idempotent ack

Why this is right for MVP debugging:

- Retry behavior is deterministic and easy to reason about.
- Fewer ambiguous race-condition outcomes.

Scale-up target (100+ users):

- Keep same contract; add observability metrics for duplicate/retry rates.

Migration trigger:

- N/A (this is intended to remain stable long-term).

---


### 6) Time authority and skew tolerance

Question:

- Broker authoritative time vs phone authoritative or dual-clock model.

MVP/home (locked):

- Broker time is authoritative for lifecycle decisions.
- Phone timestamps are metadata only.

Skew policy (locked):

- Accept phone-submitted timestamps within `+/-120s` for telemetry sanity checks.
- TTL and timeout transitions are always decided by broker clock.

Why this is right for MVP debugging:

- Single source of truth for expiry and timeout behavior.
- Avoids cross-device clock disagreement during incident triage.

Scale-up target (100+ users):

- Keep broker authoritative model.
- Add clock-drift observability and alerts.

Migration trigger:

- N/A (intended long-term default).

---


### 7) Error model shape

Question:

- Flat `error_code` responses vs structured error metadata.

MVP/home (locked):

- Use structured error responses while keeping `error_code` as stable public contract.

Required fields for non-success terminal responses (locked):

- `error_code` (stable, additive-only)
- `source` (`BROKER|PHONE|BANK|ICLOUD`)
- `stage` (`APPROVAL|AUTH|NAVIGATION|DOWNLOAD|INGEST|VERIFY`)
- `retriable` (boolean)

Optional field:

- `error_message` (sanitized and length-bounded)

Why this is right for MVP debugging:

- Better triage and retry decisions with little additional complexity.
- Aligns with logging and observability strategy.

Scale-up target (100+ users):

- Keep same shape; add subtype fields only if needed.

Migration trigger:

- N/A (intended long-term contract).

---


### 8) API versioning strategy

Question:

- Implicit unversioned endpoints vs explicit versioning now.

MVP/home (locked):

- Use explicit `/v1` path versioning now.

Versioning policy (locked):

- Additive, backward-compatible changes within `v1`.
- Breaking changes require `v2`.

Why this is right for MVP debugging:

- Low immediate overhead.
- Avoids contract ambiguity and migration surprises later.

Scale-up target (100+ users):

- Keep explicit versioning discipline.
- Introduce deprecation windows and compatibility notices.

Migration trigger:

- N/A (intended long-term contract).

---

## Pending Decisions

- None.
