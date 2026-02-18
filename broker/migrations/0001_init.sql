PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS schema_migrations (
  id TEXT PRIMARY KEY,
  applied_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS pending_requests (
  id TEXT PRIMARY KEY,
  agent_identity TEXT NOT NULL,
  agent_request_id TEXT,
  request_type TEXT NOT NULL,
  parameters_json TEXT NOT NULL,
  idempotency_key TEXT,
  nonce TEXT NOT NULL UNIQUE,
  signed_envelope_json TEXT NOT NULL,
  status TEXT NOT NULL,
  decision TEXT,
  decision_at TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  approval_expires_at TEXT NOT NULL,
  execution_started_at TEXT,
  execution_timeout_at TEXT,
  result_file_path TEXT,
  result_sha256 TEXT,
  completion_nonce TEXT UNIQUE,
  completed_at TEXT,
  error_code TEXT,
  error_source TEXT,
  error_stage TEXT,
  error_retriable INTEGER,
  error_message TEXT
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_pending_idempotency
  ON pending_requests(agent_identity, idempotency_key)
  WHERE idempotency_key IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_pending_status_expires
  ON pending_requests(status, approval_expires_at);

CREATE INDEX IF NOT EXISTS idx_pending_created
  ON pending_requests(created_at, id);

CREATE TABLE IF NOT EXISTS completion_manifests (
  request_id TEXT PRIMARY KEY REFERENCES pending_requests(id) ON DELETE CASCADE,
  filename TEXT NOT NULL,
  sha256 TEXT NOT NULL,
  bytes INTEGER NOT NULL,
  completed_at TEXT NOT NULL,
  nonce TEXT NOT NULL UNIQUE,
  signature TEXT NOT NULL,
  manifest_json TEXT NOT NULL,
  verified_at TEXT NOT NULL
);
