import { env } from "./env";
import { authenticateAgent, authenticatePhone } from "./auth/tokens";
import { migrate } from "./db/migrate";
import { startIcloudReconciler } from "./icloud/ingest";
import { logEvent } from "./logging/logger";
import { buildSignedEnvelope } from "./requests/envelope";
import {
  applyDecision,
  expireExecutionTimeouts,
  expirePendingApprovals,
  findById,
  findByIdForAgent,
  findByIdempotency,
  insertRequest,
  listPendingEnvelopes,
  listRequests,
  reportFailure,
  type PendingRequestRow,
} from "./requests/repo";
import type { Decision, ErrorMeta, RequestStatus } from "./types";
import { NON_TERMINAL_STATUSES, REQUEST_STATUSES } from "./types";
import { addSecondsIso, nowIso } from "./util/time";
import { canonicalStringify } from "./util/canonicalJson";
import { json, readJsonWithLimit } from "./util/http";
import { allowRate } from "./util/rateLimit";
import { sendTelegramNudge } from "./telegram/notifier";

const APPROVAL_TTL_MINUTES = 5;
const EXECUTION_TIMEOUT_SECONDS = 10 * 60;

function badRequest(error_code: string, message?: string): Response {
  return json(400, {
    error_code,
    source: "BROKER",
    stage: "APPROVAL",
    retriable: false,
    ...(message ? { error_message: message } : {}),
  });
}

function statusPayload(row: PendingRequestRow): Record<string, unknown> {
  const base: Record<string, unknown> = {
    request_id: row.id,
    status: row.status,
    created_at: row.created_at,
    updated_at: row.updated_at,
  };

  if (NON_TERMINAL_STATUSES.has(row.status)) {
    return {
      ...base,
      approval_expires_at: row.approval_expires_at,
      execution_timeout_at: row.execution_timeout_at,
    };
  }

  if (row.status === "COMPLETED") {
    return {
      ...base,
      file_path: row.result_file_path,
      completed_at: row.completed_at,
      result_sha256: row.result_sha256,
    };
  }

  if (row.status === "FAILED" || row.status === "DENIED" || row.status === "EXPIRED") {
    return {
      ...base,
      error_code: row.error_code,
      source: row.error_source,
      stage: row.error_stage,
      retriable: row.error_retriable === 1,
      ...(row.error_message ? { error_message: row.error_message } : {}),
    };
  }

  return base;
}

function ensureStatus(value: string | null): RequestStatus | null {
  if (!value) return null;
  if ((REQUEST_STATUSES as readonly string[]).includes(value)) {
    return value as RequestStatus;
  }
  return null;
}

function requestFingerprint(input: { type: string; month: number; year: number }): string {
  return input.type + ":" + canonicalStringify({ month: input.month, year: input.year });
}

function idempotencyMatches(existing: PendingRequestRow, fingerprint: string): boolean {
  const existingFingerprint =
    existing.idempotency_fingerprint ?? (existing.request_type + ":" + existing.parameters_json);
  return existingFingerprint === fingerprint;
}

async function handleAgentCreateRequest(req: Request): Promise<Response> {
  const auth = await authenticateAgent(req.headers.get("authorization"));
  if (!auth.ok) return json(auth.status, { error_code: auth.error });

  if (!allowRate({ identity: auth.identity, perTokenPerMinute: 60, globalPerMinute: 300 })) {
    return json(429, { error_code: "RATE_LIMITED", source: "BROKER", stage: "APPROVAL", retriable: true });
  }

  type Input = {
    type: "statement";
    month: number;
    year: number;
    agent_request_id?: string;
    idempotency_key?: string;
  };

  let body: Input;
  try {
    body = await readJsonWithLimit<Input>(req);
  } catch (err) {
    const code = err instanceof Error ? err.message : "INVALID_REQUEST";
    return badRequest(code);
  }

  if (body.type !== "statement") return badRequest("INVALID_REQUEST_TYPE");
  if (!Number.isInteger(body.month) || body.month < 1 || body.month > 12) {
    return badRequest("MISSING_FIELD", "month must be 1-12");
  }
  if (!Number.isInteger(body.year) || body.year < 2000 || body.year > 2100) {
    return badRequest("MISSING_FIELD", "year must be valid");
  }

  const fingerprint = requestFingerprint(body);

  if (body.idempotency_key) {
    const existing = findByIdempotency({
      agentIdentity: auth.identity,
      idempotencyKey: body.idempotency_key,
    });
    if (existing) {
      if (!idempotencyMatches(existing, fingerprint)) {
        return json(409, {
          error_code: "IDEMPOTENCY_CONFLICT",
          source: "BROKER",
          stage: "APPROVAL",
          retriable: false,
          error_message: "idempotency key reused with different payload",
        });
      }

      return json(NON_TERMINAL_STATUSES.has(existing.status) ? 202 : 200, statusPayload(existing));
    }
  }

  const requestId = crypto.randomUUID();
  const envelope = await buildSignedEnvelope({
    requestId,
    month: body.month,
    year: body.year,
    approvalTtlMinutes: APPROVAL_TTL_MINUTES,
  });

  insertRequest({
    id: requestId,
    agentIdentity: auth.identity,
    agentRequestId: body.agent_request_id,
    requestType: "statement",
    parametersJson: JSON.stringify({ month: body.month, year: body.year }),
    idempotencyKey: body.idempotency_key,
    idempotencyFingerprint: fingerprint,
    nonce: envelope.nonce,
    signedEnvelopeJson: JSON.stringify(envelope),
    approvalExpiresAt: envelope.approval_expires_at,
  });

  logEvent({
    event_name: "request_created",
    severity: "INFO",
    service: "broker",
    environment: env.NODE_ENV,
    request_id: requestId,
    correlation_id: requestId,
    status_after: "PENDING_APPROVAL",
    bank_id: "default",
    period_month: body.month,
    period_year: body.year,
    agent_request_id: body.agent_request_id,
  });

  logEvent({
    event_name: "request_presented_to_phone",
    severity: "INFO",
    service: "broker",
    environment: env.NODE_ENV,
    request_id: requestId,
    correlation_id: requestId,
    status_before: "PENDING_APPROVAL",
    status_after: "PENDING_APPROVAL",
  });

  sendTelegramNudge({
    requestId,
    month: body.month,
    year: body.year,
  }).catch(() => {});

  return json(202, {
    request_id: requestId,
    status: "PENDING_APPROVAL",
    created_at: envelope.issued_at,
    approval_expires_at: envelope.approval_expires_at,
  });
}

async function handleAgentGetRequest(req: Request, id: string): Promise<Response> {
  const auth = await authenticateAgent(req.headers.get("authorization"));
  if (!auth.ok) return json(auth.status, { error_code: auth.error });

  if (!allowRate({ identity: auth.identity, perTokenPerMinute: 60, globalPerMinute: 300 })) {
    return json(429, { error_code: "RATE_LIMITED", source: "BROKER", stage: "APPROVAL", retriable: true });
  }

  expirePendingApprovals();
  expireExecutionTimeouts();

  const row = findByIdForAgent({ requestId: id, agentIdentity: auth.identity });
  if (!row) return json(404, { error_code: "REQUEST_NOT_FOUND" });

  return json(NON_TERMINAL_STATUSES.has(row.status) ? 202 : 200, statusPayload(row));
}

async function handleAgentListRequests(req: Request): Promise<Response> {
  const auth = await authenticateAgent(req.headers.get("authorization"));
  if (!auth.ok) return json(auth.status, { error_code: auth.error });

  if (!allowRate({ identity: auth.identity, perTokenPerMinute: 60, globalPerMinute: 300 })) {
    return json(429, { error_code: "RATE_LIMITED", source: "BROKER", stage: "APPROVAL", retriable: true });
  }

  const url = new URL(req.url);
  const limitRaw = Number(url.searchParams.get("limit") ?? "50");
  const limit = Number.isFinite(limitRaw)
    ? Math.max(1, Math.min(200, Math.floor(limitRaw)))
    : 50;

  const cursor = url.searchParams.get("cursor");
  const status = ensureStatus(url.searchParams.get("status"));
  if (url.searchParams.get("status") && !status) {
    return badRequest("INVALID_STATUS");
  }

  const result = listRequests({
    agentIdentity: auth.identity,
    limit,
    cursor,
    status,
  });

  return json(200, {
    requests: result.rows.map((row) => statusPayload(row)),
    next_cursor: result.nextCursor,
  });
}

async function handlePhonePending(req: Request): Promise<Response> {
  const auth = await authenticatePhone(req.headers.get("authorization"));
  if (!auth.ok) return json(auth.status, { error_code: auth.error });

  if (!allowRate({ identity: auth.identity, perTokenPerMinute: 120, globalPerMinute: 300 })) {
    return json(429, { error_code: "RATE_LIMITED", source: "BROKER", stage: "APPROVAL", retriable: true });
  }

  expirePendingApprovals();
  expireExecutionTimeouts();

  const pending = listPendingEnvelopes(100).map((row) => ({
    envelope: JSON.parse(row.signed_envelope_json),
  }));

  return json(200, { requests: pending });
}

async function handlePhoneDecision(req: Request, id: string): Promise<Response> {
  const auth = await authenticatePhone(req.headers.get("authorization"));
  if (!auth.ok) return json(auth.status, { error_code: auth.error });

  if (!allowRate({ identity: auth.identity, perTokenPerMinute: 120, globalPerMinute: 300 })) {
    return json(429, { error_code: "RATE_LIMITED", source: "BROKER", stage: "APPROVAL", retriable: true });
  }

  type Input = { decision: Decision; decided_at?: string };
  let body: Input;
  try {
    body = await readJsonWithLimit<Input>(req);
  } catch (err) {
    return badRequest(err instanceof Error ? err.message : "INVALID_JSON");
  }

  if (body.decision !== "APPROVE" && body.decision !== "DENY") {
    return badRequest("INVALID_DECISION");
  }

  expirePendingApprovals();
  expireExecutionTimeouts();

  const row = findById({ requestId: id });
  if (!row) return json(404, { error_code: "REQUEST_NOT_FOUND" });

  const decisionResult = applyDecision({
    request: row,
    decision: body.decision,
    executionTimeoutAt: addSecondsIso(nowIso(), EXECUTION_TIMEOUT_SECONDS),
  });

  if (!decisionResult.ok) {
    return json(decisionResult.status, {
      error_code: decisionResult.error,
      source: "BROKER",
      stage: "APPROVAL",
      retriable: false,
    });
  }

  if (!decisionResult.idempotent) {
    if (body.decision === "APPROVE") {
      logEvent({
        event_name: "request_approved",
        severity: "INFO",
        service: "broker",
        environment: env.NODE_ENV,
        request_id: id,
        correlation_id: id,
        status_before: row.status,
        status_after: "APPROVED",
      });
      logEvent({
        event_name: "execution_started",
        severity: "INFO",
        service: "broker",
        environment: env.NODE_ENV,
        request_id: id,
        correlation_id: id,
        status_before: "APPROVED",
        status_after: "EXECUTING",
      });
    } else {
      logEvent({
        event_name: "request_denied",
        severity: "WARN",
        service: "broker",
        environment: env.NODE_ENV,
        request_id: id,
        correlation_id: id,
        status_before: row.status,
        status_after: "DENIED",
      });
    }
  }

  const latest = findById({ requestId: id });
  if (!latest) return json(500, { error_code: "REQUEST_NOT_FOUND" });

  return json(200, {
    request_id: id,
    status: latest.status,
    idempotent: decisionResult.idempotent,
  });
}

async function handlePhoneFailure(req: Request, id: string): Promise<Response> {
  const auth = await authenticatePhone(req.headers.get("authorization"));
  if (!auth.ok) return json(auth.status, { error_code: auth.error });

  if (!allowRate({ identity: auth.identity, perTokenPerMinute: 120, globalPerMinute: 300 })) {
    return json(429, { error_code: "RATE_LIMITED", source: "BROKER", stage: "APPROVAL", retriable: true });
  }

  type Input = ErrorMeta & { failed_at?: string };
  let body: Input;
  try {
    body = await readJsonWithLimit<Input>(req);
  } catch (err) {
    return badRequest(err instanceof Error ? err.message : "INVALID_JSON");
  }

  if (!body.error_code || !body.source || !body.stage || typeof body.retriable !== "boolean") {
    return badRequest("MISSING_FIELD");
  }

  const row = findById({ requestId: id });
  if (!row) return json(404, { error_code: "REQUEST_NOT_FOUND" });

  const result = reportFailure({
    request: row,
    error: {
      error_code: body.error_code,
      source: body.source,
      stage: body.stage,
      retriable: body.retriable,
      error_message: body.error_message,
    },
  });

  if (!result.ok) {
    return json(result.status, {
      error_code: result.error,
      source: "BROKER",
      stage: "DOWNLOAD",
      retriable: false,
    });
  }

  if (!result.idempotent) {
    logEvent({
      event_name: "execution_failed",
      severity: "WARN",
      service: "broker",
      environment: env.NODE_ENV,
      request_id: id,
      correlation_id: id,
      status_before: row.status,
      status_after: "FAILED",
      error_code: body.error_code,
      source: body.source,
      stage: body.stage,
      retriable: body.retriable,
    });
  }

  const latest = findById({ requestId: id });
  if (!latest) return json(500, { error_code: "REQUEST_NOT_FOUND" });

  return json(200, {
    request_id: id,
    status: latest.status,
    idempotent: result.idempotent,
  });
}

async function handleRequest(req: Request): Promise<Response> {
  const url = new URL(req.url);
  const path = url.pathname;

  if (req.method === "GET" && path === "/healthz") {
    return json(200, { ok: true });
  }

  if (req.method === "POST" && path === "/v1/request") {
    return handleAgentCreateRequest(req);
  }

  if (req.method === "GET" && path === "/v1/requests") {
    return handleAgentListRequests(req);
  }

  const getRequestMatch = path.match(/^\/v1\/request\/([^/]+)$/);
  if (req.method === "GET" && getRequestMatch) {
    return handleAgentGetRequest(req, decodeURIComponent(getRequestMatch[1]));
  }

  if (req.method === "GET" && path === "/v1/phone/requests/pending") {
    return handlePhonePending(req);
  }

  const decisionMatch = path.match(/^\/v1\/phone\/requests\/([^/]+)\/decision$/);
  if (req.method === "POST" && decisionMatch) {
    return handlePhoneDecision(req, decodeURIComponent(decisionMatch[1]));
  }

  const failureMatch = path.match(/^\/v1\/phone\/requests\/([^/]+)\/failure$/);
  if (req.method === "POST" && failureMatch) {
    return handlePhoneFailure(req, decodeURIComponent(failureMatch[1]));
  }

  return json(404, { error_code: "NOT_FOUND" });
}

export { handleRequest };

export function startBrokerServer(): void {
  migrate();
  startIcloudReconciler();
  setInterval(() => {
    expirePendingApprovals();
    expireExecutionTimeouts();
  }, 1_000);

  Bun.serve({
    hostname: env.BROKER_HOST,
    port: env.BROKER_PORT,
    fetch: handleRequest,
  });

  logEvent({
    event_name: "broker_started",
    severity: "INFO",
    service: "broker",
    environment: env.NODE_ENV,
  });
}

if (import.meta.main) {
  startBrokerServer();
}
