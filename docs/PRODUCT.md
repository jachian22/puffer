# Secure Data Fetcher - Product Brief (MVP)

Last updated: 2026-02-17
References: `SECURE_DATA_FETCHER_MVP_TECH_SPEC_V1_1.md`

## 1) What We Are Building

Secure Data Fetcher is a phone-trust-boundary workflow for retrieving bank statement PDFs.

The core product promise:

- The user explicitly approves every fetch with Face ID.
- Bank credentials stay on iPhone only.
- Broker and agent never receive credentials or browser session secrets.

## 2) Problem Statement

Users want to automate statement retrieval for downstream tools/agents, but do not want:

- credentials stored on desktop services
- silent background execution
- broad standing permissions without explicit per-request consent

Existing automation patterns optimize convenience first. This product optimizes safety and user control first.

## 3) Target User (MVP)

Primary user:

- Technical individual running local agent workflows
- Comfortable self-hosting a local broker
- Strong preference for explicit approval and device-isolated credentials

## 4) Jobs To Be Done

When an agent needs a statement PDF, the user wants to:

1. See exactly what month/year is being requested
2. Approve or deny in seconds
3. Keep credentials confined to their iPhone
4. Receive a raw statement PDF for downstream use

## 5) Product Principles

- Security over convenience
- Explicit user intent over automation
- Narrow scope over platform breadth
- Observable state over hidden workflow
- Deterministic failure over ambiguous behavior

## 6) MVP Scope

In scope:

- Single hardcoded bank flow
- Read-only statement PDF retrieval
- iPhone foreground execution only
- Telegram used as nudge channel
- Broker status polling and iCloud file return

Out of scope:

- Multi-bank support
- Write actions
- Background automation
- Policy-based auto-approval
- Data transformation/redaction
- Web dashboard

## 7) End-to-End User Journey

1. Agent submits statement request to broker.
2. Broker creates signed request envelope and sends Telegram nudge.
3. User opens iPhone app.
4. App pulls pending signed request, verifies signature/replay/expiry.
5. User approves with Face ID or denies.
6. If approved, app executes bank flow in WKWebView.
7. App writes PDF + signed manifest to iCloud inbox.
8. Broker verifies manifest and file digest, then marks request terminal.
9. Agent polls broker for terminal status.

## 8) Security and Trust Model (Product Level)

Trust boundaries:

- Trusted execution: iPhone app + Keychain + biometric gate
- Untrusted messaging: Telegram
- Semi-trusted transport: iCloud Drive sync
- Broker trusted for orchestration and signature validation only

Security expectations:

- Requests and completions are signature-verified
- Replay protection is enforced via nonce uniqueness
- Terminal states are monotonic and auditable

## 9) UX Requirements (MVP)

Approval screen must include:

- bank identifier
- statement period
- request id (shortened)
- remaining approval window
- explicit Approve (Face ID) and Deny actions

Failure UX must be clear and actionable:

- distinguish approval timeout vs execution failure
- use stable error codes for support/debugging

## 10) Success Metrics

North-star:

- Secure completion rate = `% requests completed without security policy violations`

MVP operational metrics:

- Approval conversion rate (approved / presented)
- Median request-to-terminal latency
- Failure rate by error code
- Replay/tamper rejection count
- False completion acceptance count (target: zero)

## 11) Launch Readiness Criteria

Must-have before first real use:

- Signed envelope and manifest validation live
- Replay protections enforced
- Canonical state machine enforced in DB transitions
- iCloud reconciliation loop implemented
- Integration tests for tamper, replay, missed watcher events
- Audit logs available for request lifecycle

## 12) Risks and Mitigations

Risk: bank DOM changes break automation

- Mitigation: deterministic navigation error codes, screenshot-on-failure, script versioning

Risk: iCloud watch misses events

- Mitigation: startup + periodic reconciliation and file stability checks

Risk: user confusion around Telegram role

- Mitigation: explicit UX copy that Telegram is notification-only, approval happens in app

Risk: local broker endpoint abuse

- Mitigation: mandatory bearer auth, loopback bind default, rate limits

## 13) Product Considerations Beyond Implementation

Privacy disclosures:

- clearly state what data is stored locally on phone and broker
- state that statement PDFs sync via iCloud

Incident handling:

- define user-visible guidance for suspicious or repeated failed requests

Recovery UX:

- easy credential reset flow
- request history view with terminal outcomes

Compliance posture:

- avoid absolute marketing claims ("never over network")
- use precise claims consistent with actual protocol

## 14) Post-MVP Product Direction

Phase 2:

- multi-bank support with explicit per-bank setup
- optional structured extraction (in addition to raw PDF)

Phase 3:

- constrained pre-approval policies with revocation
- richer operational dashboard

Phase 4:

- additional providers beyond banking
- stronger local attestation and hardware-backed approval options
