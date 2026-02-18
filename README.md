# 🐡 Puffer - Secure Data Fetcher

A human-approved, phone-executed system for retrieving sensitive personal data (like bank statements) with explicit biometric approval.

## The Problem: Agentic AI Needs Data, But Credentials Are Sacred

Agentic software like Claude Code is transforming how we work with computers. These AI agents can analyze documents, process financial data, and automate complex tasks. But they hit a wall when they need access to sensitive data behind authentication.

Consider this scenario: You're using Claude Code for financial analysis and need your latest bank statement. Today, you have three bad options:

1. **Manual download** - Break your flow, log in yourself, download the PDF, tell the agent where to find it. Every. Single. Time.
2. **Give credentials to the agent** - Store your bank password in a file the agent can read. Your credentials are now exposed to every tool in the chain, sitting in plaintext on disk, potentially logged, potentially exfiltrated.
3. **Use a credential manager the agent can access** - Only marginally better. The agent still gets raw access to your credentials when it asks.

**The core problem**: There's no way for an AI agent to request authenticated data without either constant human intervention or dangerous credential exposure.

## The Solution: Human-in-the-Loop Execution

Puffer solves this by separating *what the agent wants* from *how it gets it*:

```
Agent knows:  "I need the January 2026 bank statement"
Agent never knows:  Your username, password, or how to log in
```

The magic is that **execution happens on your iPhone**, where credentials live in the Secure Enclave and are protected by Face ID. The agent never sees credentials. Your computer never sees credentials. Only your phone touches the bank's login page.

![Puffer Architecture Diagram](docs/architecture.png)

## Request Flow

1. **Agent requests data** - Claude Code calls the broker: "I need the January 2026 statement"
2. **Broker creates signed request** - Cryptographically signed envelope with nonce, expiry, and request details
3. **User gets notified** - Telegram message nudges you to open the app
4. **You approve on iPhone** - See exactly what's being requested, approve with Face ID
5. **Phone executes** - WKWebView logs into your bank, downloads the PDF, writes it to iCloud
6. **Broker verifies** - Checks signed manifest, verifies PDF hash, marks complete
7. **Agent gets data** - Polls for status, receives file path when ready

## Security Properties

| Property | How It's Achieved |
|----------|-------------------|
| **Credentials never leave iPhone** | Stored in Keychain with biometric access control; sent only to bank over TLS |
| **Every request requires explicit approval** | Face ID gate on iPhone; no background execution |
| **Agent can't forge requests** | HMAC-signed envelopes with shared secret |
| **Replay attacks blocked** | Unique nonces tracked for 24+ hours |
| **Completion can't be spoofed** | Signed manifests with SHA-256 file hashes |
| **No credential exposure in logs** | Credentials never touch broker or agent |

## Trust Boundaries

```
┌───────────────────────────────────────────────────────┐
│                  TRUSTED EXECUTION                    │
│                                                       │
│   iPhone App + iOS Keychain + Secure Enclave         │
│   (Credentials live here and only here)               │
└───────────────────────────────────────────────────────┘
                           │
                           │ TLS to bank only
                           ▼
┌───────────────────────────────────────────────────────┐
│              SEMI-TRUSTED SYNC CHANNEL                │
│                                                       │
│   iCloud Drive (Apple-managed encryption,             │
│   not E2E encrypted for this protocol)                │
└───────────────────────────────────────────────────────┘
                           │
                           ▼
┌───────────────────────────────────────────────────────┐
│          TRUSTED ORCHESTRATION (NO CREDENTIALS)       │
│                                                       │
│   Broker (coordinates requests, verifies signatures,  │
│   never sees credentials)                             │
└───────────────────────────────────────────────────────┘
                           │
                           ▼
┌───────────────────────────────────────────────────────┐
│               UNTRUSTED NOTIFICATION                  │
│                                                       │
│   Telegram (nudge only, not authoritative)            │
└───────────────────────────────────────────────────────┘
```

## Why This Matters for Agentic Software

As AI agents become more capable, they'll need access to more of our digital lives. The current paradigm of "give the agent your password" doesn't scale. Puffer demonstrates a pattern where:

- **Agents request, humans approve** - Every sensitive operation is gated by explicit human consent
- **Execution happens in trusted enclaves** - Your phone's Secure Enclave, not a random subprocess
- **Credentials are never delegated** - The agent describes *what* it needs, not *how* to get it

This is the difference between giving someone your house key and having them ring the doorbell.

## Components

### Broker (`/broker`)
TypeScript service running on your computer. Handles request intake from agents, state management, Telegram notifications, and iCloud inbox monitoring.

### iPhone App (`/ios`)
Swift app with credential management, approval UI, and WKWebView automation engine.

## Quick Start

See [broker/README.md](broker/README.md) for broker setup instructions.

## License

Private - All rights reserved.
