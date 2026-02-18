ALTER TABLE pending_requests ADD COLUMN idempotency_fingerprint TEXT;

UPDATE pending_requests
SET idempotency_fingerprint = request_type || ':' || parameters_json
WHERE idempotency_key IS NOT NULL
  AND idempotency_fingerprint IS NULL;
