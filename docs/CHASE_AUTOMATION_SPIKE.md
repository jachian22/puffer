# Chase Automation Spike Notes

Last updated: 2026-02-17

## Objective

Document what we can validate before authenticated selector discovery, and define a concrete first-run discovery procedure.

## Public Endpoint Probes (Header/Redirect)

Commands run:

- `curl -I -L --max-redirs 5 https://chase.com`
- `curl -I -L --max-redirs 8 "https://secure.chase.com/web/auth/dashboard#/dashboard/documents/myDocs/index;mode=documents"`

Observed:

- `https://chase.com` redirects to `https://www.chase.com/`.
- `secure.chase.com` dashboard/documents URL responds with `200` and strict security headers.
- Dashboard path appears accessible only within authenticated flow context.

Implications:

- Initial navigation should treat `www.chase.com` and `secure.chase.com` as expected hosts.
- Login success detection should include hostname/path checks, not brittle title matching.

## MVP Unknowns (Requires Authenticated Discovery)

- Final login form selectors for username/password.
- Exact post-login path differences for business context.
- Statement list selectors for bank vs credit card statements.
- PDF download trigger element selectors and timing behavior.
- Any challenge/CAPTCHA edge paths under automation.

## First Device Discovery Procedure

1. Build iPhone app with WKWebView debug instrumentation enabled.
2. Run login manually once and capture:
- current URL changes
- page HTML snippets around login fields
- candidate selector snapshots (sanitized)
3. Navigate to statements/documents manually and capture:
- account switch controls (if any)
- period dropdown/select controls
- download button/link selector candidates
4. Save selector candidates into Chase script config constants.
5. Validate for:
- one personal statement month
- one business statement month
- one credit card statement month

## Required Debug Instrumentation (Sanitized)

- URL transition log per navigation step.
- Selector existence checks (boolean only).
- Optional viewport screenshot on failure (no credential fields focused).
- Explicit error mapping on each failed step.

## Exit Criteria for Spike

- Working selector set for at least one statement retrieval path.
- Confirmed behavior for SMS 2FA interruption and resume.
- Clear list of unsupported edge cases for post-MVP backlog.

## Current Recommendation

- Keep PDF-first in MVP due known statement path certainty.
- Add CSV extraction only after selectors and path stability are proven.
