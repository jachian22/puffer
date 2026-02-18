import { db } from "../db/client";
import type { Decision, ErrorMeta, RequestStatus } from "../types";
import { NON_TERMINAL_STATUSES } from "../types";
import { canTransition } from "./state";
import { nowIso } from "../util/time";

export type PendingRequestRow = {
  id: string;
  agent_identity: string;
  agent_request_id: string | null;
  request_type: string;
  parameters_json: string;
  idempotency_key: string | null;
  idempotency_fingerprint: string | null;
  nonce: string;
  signed_envelope_json: string;
  status: RequestStatus;
  decision: Decision | null;
  decision_at: string | null;
  created_at: string;
  updated_at: string;
  approval_expires_at: string;
  execution_started_at: string | null;
  execution_timeout_at: string | null;
  result_file_path: string | null;
  result_sha256: string | null;
  completion_nonce: string | null;
  completed_at: string | null;
  error_code: string | null;
  error_source: string | null;
  error_stage: string | null;
  error_retriable: number | null;
  error_message: string | null;
};

type Cursor = { created_at: string; id: string };

function parseCursor(cursor: string | null): Cursor | null {
  if (!cursor) return null;
  try {
    const json = Buffer.from(cursor, "base64url").toString("utf8");
    const parsed = JSON.parse(json) as Cursor;
    if (!parsed.created_at || !parsed.id) return null;
    return parsed;
  } catch {
    return null;
  }
}

function encodeCursor(cursor: Cursor): string {
  return Buffer.from(JSON.stringify(cursor), "utf8").toString("base64url");
}

export function expirePendingApprovals(now = nowIso()): number {
  return db()
    .query(
      "UPDATE pending_requests SET status = 'EXPIRED', updated_at = ?, error_code = 'APPROVAL_EXPIRED', error_source = 'BROKER', error_stage='APPROVAL', error_retriable=0 WHERE status = 'PENDING_APPROVAL' AND approval_expires_at < ?;"
    )
    .run(now, now).changes;
}

export function findById(params: {
  requestId: string;
}): PendingRequestRow | null {
  return db()
    .query("SELECT * FROM pending_requests WHERE id = ? LIMIT 1;")
    .get(params.requestId) as PendingRequestRow | null;
}

export function findByIdForAgent(params: {
  requestId: string;
  agentIdentity: string;
}): PendingRequestRow | null {
  return db()
    .query(
      "SELECT * FROM pending_requests WHERE id = ? AND agent_identity = ? LIMIT 1;"
    )
    .get(params.requestId, params.agentIdentity) as PendingRequestRow | null;
}

export function findByIdempotency(params: {
  agentIdentity: string;
  idempotencyKey: string;
}): PendingRequestRow | null {
  return db()
    .query(
      "SELECT * FROM pending_requests WHERE agent_identity = ? AND idempotency_key = ? LIMIT 1;"
    )
    .get(params.agentIdentity, params.idempotencyKey) as PendingRequestRow | null;
}

export function insertRequest(params: {
  id: string;
  agentIdentity: string;
  agentRequestId?: string;
  requestType: "statement";
  parametersJson: string;
  idempotencyKey?: string;
  idempotencyFingerprint?: string;
  nonce: string;
  signedEnvelopeJson: string;
  approvalExpiresAt: string;
}): void {
  const now = nowIso();
  db()
    .query(
      "INSERT INTO pending_requests (id, agent_identity, agent_request_id, request_type, parameters_json, idempotency_key, idempotency_fingerprint, nonce, signed_envelope_json, status, created_at, updated_at, approval_expires_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'PENDING_APPROVAL', ?, ?, ?);"
    )
    .run(
      params.id,
      params.agentIdentity,
      params.agentRequestId ?? null,
      params.requestType,
      params.parametersJson,
      params.idempotencyKey ?? null,
      params.idempotencyFingerprint ?? null,
      params.nonce,
      params.signedEnvelopeJson,
      now,
      now,
      params.approvalExpiresAt
    );
}

export function listRequests(params: {
  agentIdentity: string;
  limit: number;
  cursor?: string | null;
  status?: RequestStatus | null;
}): { rows: PendingRequestRow[]; nextCursor: string | null } {
  const parsedCursor = parseCursor(params.cursor ?? null);
  const queryParts = [
    "SELECT * FROM pending_requests WHERE agent_identity = ?",
  ];
  const args: unknown[] = [params.agentIdentity];

  if (params.status) {
    queryParts.push("AND status = ?");
    args.push(params.status);
  }

  if (parsedCursor) {
    queryParts.push("AND (created_at < ? OR (created_at = ? AND id < ?))");
    args.push(parsedCursor.created_at, parsedCursor.created_at, parsedCursor.id);
  }

  queryParts.push("ORDER BY created_at DESC, id DESC LIMIT ?");
  args.push(params.limit + 1);

  const rows = db()
    .query(queryParts.join(" "))
    .all(...(args as Array<string | number | null>)) as PendingRequestRow[];

  let nextCursor: string | null = null;
  if (rows.length > params.limit) {
    const tail = rows[params.limit - 1];
    nextCursor = encodeCursor({ created_at: tail.created_at, id: tail.id });
    rows.splice(params.limit);
  }

  return { rows, nextCursor };
}

export function listPendingEnvelopes(limit = 100): PendingRequestRow[] {
  return db()
    .query(
      "SELECT * FROM pending_requests WHERE status = 'PENDING_APPROVAL' ORDER BY created_at ASC LIMIT ?;"
    )
    .all(limit) as PendingRequestRow[];
}

export function applyDecision(params: {
  request: PendingRequestRow;
  decision: Decision;
  executionTimeoutAt: string;
  now?: string;
}): { ok: true; status: RequestStatus; idempotent: boolean } | { ok: false; status: number; error: string } {
  const now = params.now ?? nowIso();
  const current = params.request.status;

  if (current === "PENDING_APPROVAL") {
    if (params.decision === "DENY") {
      if (!canTransition(current, "DENIED")) {
        return { ok: false, status: 500, error: "INVALID_STATE_TRANSITION" };
      }
      const denyResult = db()
        .query(
          "UPDATE pending_requests SET status='DENIED', decision='DENY', decision_at=?, updated_at=?, error_code='DENIED_BY_USER', error_source='PHONE', error_stage='APPROVAL', error_retriable=0 WHERE id = ? AND status='PENDING_APPROVAL';"
        )
        .run(now, now, params.request.id);
      if (denyResult.changes !== 1) {
        return { ok: false, status: 409, error: "INVALID_REQUEST_STATE" };
      }
      return { ok: true, status: "DENIED", idempotent: false };
    }

    if (!canTransition(current, "APPROVED") || !canTransition("APPROVED", "EXECUTING")) {
      return { ok: false, status: 500, error: "INVALID_STATE_TRANSITION" };
    }

    let ok = false;
    db().transaction(() => {
      const step1 = db()
        .query(
          "UPDATE pending_requests SET status='APPROVED', decision='APPROVE', decision_at=?, updated_at=? WHERE id = ? AND status='PENDING_APPROVAL';"
        )
        .run(now, now, params.request.id);
      if (step1.changes !== 1) return;

      const step2 = db()
        .query(
          "UPDATE pending_requests SET status='EXECUTING', execution_started_at=?, execution_timeout_at=?, updated_at=? WHERE id = ? AND status='APPROVED';"
        )
        .run(now, params.executionTimeoutAt, now, params.request.id);

      ok = step2.changes === 1;
    })();

    if (!ok) {
      return { ok: false, status: 409, error: "INVALID_REQUEST_STATE" };
    }

    return { ok: true, status: "EXECUTING", idempotent: false };
  }

  if (current === "DENIED" && params.request.decision === "DENY" && params.decision === "DENY") {
    return { ok: true, status: current, idempotent: true };
  }

  if (
    (current === "EXECUTING" || current === "COMPLETED" || current === "FAILED") &&
    params.request.decision === "APPROVE" &&
    params.decision === "APPROVE"
  ) {
    return { ok: true, status: current, idempotent: true };
  }

  if (NON_TERMINAL_STATUSES.has(current)) {
    return { ok: false, status: 409, error: "INVALID_REQUEST_STATE" };
  }

  return { ok: false, status: 409, error: "DECISION_CONFLICT" };
}

export function reportFailure(params: {
  request: PendingRequestRow;
  error: ErrorMeta;
  now?: string;
}): { ok: true; status: RequestStatus; idempotent: boolean } | { ok: false; status: number; error: string } {
  const now = params.now ?? nowIso();

  if (params.request.status === "FAILED") {
    return { ok: true, status: "FAILED", idempotent: true };
  }

  if (["COMPLETED", "DENIED", "EXPIRED"].includes(params.request.status)) {
    return { ok: true, status: params.request.status, idempotent: true };
  }

  if (params.request.status !== "EXECUTING" && params.request.status !== "APPROVED") {
    return { ok: false, status: 409, error: "INVALID_REQUEST_STATE" };
  }

  if (!canTransition(params.request.status, "FAILED")) {
    return { ok: false, status: 500, error: "INVALID_STATE_TRANSITION" };
  }

  const result = db()
    .query(
      "UPDATE pending_requests SET status='FAILED', updated_at=?, error_code=?, error_source=?, error_stage=?, error_retriable=?, error_message=? WHERE id = ? AND status IN ('EXECUTING','APPROVED');"
    )
    .run(
      now,
      params.error.error_code,
      params.error.source,
      params.error.stage,
      params.error.retriable ? 1 : 0,
      params.error.error_message ?? null,
      params.request.id
    );

  if (result.changes !== 1) {
    return { ok: false, status: 409, error: "INVALID_REQUEST_STATE" };
  }

  return { ok: true, status: "FAILED", idempotent: false };
}

export function markCompleted(params: {
  requestId: string;
  filePath: string;
  sha256: string;
  completionNonce: string;
  completedAt: string;
  manifestJson: string;
  manifestSignature: string;
  filename: string;
  bytes: number;
  verifiedAt?: string;
}): boolean {
  const now = params.verifiedAt ?? nowIso();

  return db().transaction(() => {
    db()
      .query(
        "INSERT INTO completion_manifests (request_id, filename, sha256, bytes, completed_at, nonce, signature, manifest_json, verified_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);"
      )
      .run(
        params.requestId,
        params.filename,
        params.sha256,
        params.bytes,
        params.completedAt,
        params.completionNonce,
        params.manifestSignature,
        params.manifestJson,
        now
      );

    const result = db()
      .query(
        "UPDATE pending_requests SET status='COMPLETED', updated_at=?, completed_at=?, result_file_path=?, result_sha256=?, completion_nonce=?, error_code=NULL, error_source=NULL, error_stage=NULL, error_retriable=NULL, error_message=NULL WHERE id = ? AND status IN ('EXECUTING','APPROVED');"
      )
      .run(
        now,
        params.completedAt,
        params.filePath,
        params.sha256,
        params.completionNonce,
        params.requestId
      );

    if (result.changes !== 1) {
      throw new Error("completion_update_failed");
    }

    return true;
  })();
}

export function markManifestVerificationFailure(params: {
  requestId: string;
  message: string;
  now?: string;
}): void {
  const now = params.now ?? nowIso();
  db()
    .query(
      "UPDATE pending_requests SET status='FAILED', updated_at=?, error_code='MANIFEST_VERIFICATION_FAILED', error_source='BROKER', error_stage='VERIFY', error_retriable=0, error_message=? WHERE id = ? AND status IN ('APPROVED','EXECUTING');"
    )
    .run(now, params.message, params.requestId);
}


export function expireExecutionTimeouts(now = nowIso()): number {
  return db()
    .query(
      "UPDATE pending_requests SET status = 'FAILED', updated_at = ?, error_code='EXECUTION_TIMEOUT', error_source='BROKER', error_stage='DOWNLOAD', error_retriable=1, error_message='execution timeout' WHERE status = 'EXECUTING' AND execution_timeout_at IS NOT NULL AND execution_timeout_at < ?;"
    )
    .run(now, now).changes;
}
