# Secure Data Fetcher Broker

Local broker service for the Secure Data Fetcher MVP.

## Endpoints (v1)

- `POST /v1/request`
- `GET /v1/request/:request_id`
- `GET /v1/requests`
- `GET /v1/phone/requests/pending`
- `POST /v1/phone/requests/:request_id/decision`
- `POST /v1/phone/requests/:request_id/failure`
- `GET /healthz`

## Quick Start

1. Set env vars (copy `.env.example` to your shell environment).
2. Run migrations:

```bash
bun run migrate
```

3. Start server:

```bash
bun run dev
```

## Tests

```bash
bun test
```

## Notes

- Broker binds to `127.0.0.1` by default.
- Request and manifest payloads are HMAC signed.
- iCloud reconciliation loop runs every 10 seconds when `ICLOUD_INBOX_PATH` is configured.


## Launchd (optional after MVP stabilization)

Install:

```bash
./scripts/install_launchd.sh /Users/jachian/Documents/puffer
```

Uninstall:

```bash
./scripts/uninstall_launchd.sh
```
