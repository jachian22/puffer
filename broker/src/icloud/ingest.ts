import { access, readdir, readFile, stat } from "node:fs/promises";
import { constants, watch, accessSync } from "node:fs";
import { isAbsolute, join, normalize, resolve } from "node:path";
import os from "node:os";

import { env } from "../env";
import { sha256HexFromFile } from "../crypto/hmac";
import { logEvent } from "../logging/logger";
import { verifyManifest, type CompletionManifest } from "../requests/manifest";
import {
  findById,
  markCompleted,
  markManifestVerificationFailure,
} from "../requests/repo";
import { nowIso } from "../util/time";

function expandHome(pathValue: string): string {
  if (pathValue.startsWith("~/")) {
    return join(os.homedir(), pathValue.slice(2));
  }
  return pathValue;
}

export function resolveInboxPath(rawPath: string): string {
  const expanded = expandHome(rawPath.trim());
  return isAbsolute(expanded) ? normalize(expanded) : resolve(expanded);
}

function isPathWithin(parent: string, child: string): boolean {
  const parentResolved = resolve(parent);
  const childResolved = resolve(child);
  return childResolved === parentResolved || childResolved.startsWith(`${parentResolved}/`);
}

async function wait(ms: number): Promise<void> {
  await new Promise((resolvePromise) => setTimeout(resolvePromise, ms));
}

async function fileStable(path: string, pauseMs = 2000): Promise<boolean> {
  const first = await stat(path);
  await wait(pauseMs);
  const second = await stat(path);
  return (
    first.size === second.size && first.mtimeMs === second.mtimeMs && first.size > 0
  );
}

function parseManifest(jsonText: string): CompletionManifest | null {
  try {
    const parsed = JSON.parse(jsonText) as CompletionManifest;
    if (!parsed.request_id || !parsed.filename || !parsed.signature) {
      return null;
    }
    return parsed;
  } catch {
    return null;
  }
}

async function processManifestFile(inboxPath: string, manifestPath: string): Promise<void> {
  const raw = await readFile(manifestPath, "utf8");
  const manifest = parseManifest(raw);
  if (!manifest) return;

  const request = findById({ requestId: manifest.request_id });
  if (!request) return;

  const sigOk = await verifyManifest(manifest);
  if (!sigOk) {
    markManifestVerificationFailure({
      requestId: manifest.request_id,
      message: "invalid manifest signature",
    });
    logEvent({
      event_name: "manifest_verified_broker",
      severity: "ERROR",
      service: "broker",
      environment: env.NODE_ENV,
      request_id: manifest.request_id,
      correlation_id: manifest.request_id,
      status_before: request.status,
      status_after: "FAILED",
      error_code: "MANIFEST_VERIFICATION_FAILED",
      source: "BROKER",
      stage: "VERIFY",
      retriable: false,
    });
    return;
  }

  const filePath = resolve(inboxPath, manifest.filename);
  if (!isPathWithin(inboxPath, filePath)) {
    markManifestVerificationFailure({
      requestId: manifest.request_id,
      message: "path traversal rejected",
    });
    return;
  }

  try {
    await access(filePath, constants.F_OK | constants.R_OK);
  } catch {
    return;
  }

  const stable = await fileStable(filePath);
  if (!stable) {
    return;
  }

  const hash = await sha256HexFromFile(filePath);
  if (hash !== manifest.sha256) {
    markManifestVerificationFailure({
      requestId: manifest.request_id,
      message: "digest mismatch",
    });
    return;
  }

  try {
    markCompleted({
      requestId: manifest.request_id,
      filePath,
      sha256: manifest.sha256,
      completionNonce: manifest.nonce,
      completedAt: manifest.completed_at,
      manifestJson: raw,
      manifestSignature: manifest.signature,
      filename: manifest.filename,
      bytes: manifest.bytes,
      verifiedAt: nowIso(),
    });

    logEvent({
      event_name: "request_completed",
      severity: "INFO",
      service: "broker",
      environment: env.NODE_ENV,
      request_id: manifest.request_id,
      correlation_id: manifest.request_id,
      status_before: request.status,
      status_after: "COMPLETED",
    });
  } catch {
    // Duplicate nonce or already terminalized request. Treat as idempotent noop.
  }
}

export async function reconcileIcloudInbox(): Promise<void> {
  if (!env.ICLOUD_INBOX_PATH) return;

  const inboxPath = resolveInboxPath(env.ICLOUD_INBOX_PATH);
  let files: string[] = [];
  try {
    files = await readdir(inboxPath);
  } catch {
    return;
  }

  const manifests = files.filter((file) => file.endsWith(".manifest.json"));
  for (const manifest of manifests) {
    const manifestPath = join(inboxPath, manifest);
    await processManifestFile(inboxPath, manifestPath);
  }
}

export function startIcloudReconciler(): void {
  if (!env.ICLOUD_INBOX_PATH) return;

  const inboxPath = resolveInboxPath(env.ICLOUD_INBOX_PATH);
  try {
    accessSync(inboxPath, constants.F_OK | constants.R_OK);
  } catch {
    logEvent({
      event_name: "icloud_inbox_unavailable",
      severity: "ERROR",
      service: "broker",
      environment: env.NODE_ENV,
      source: "BROKER",
      stage: "INGEST",
      retriable: true,
      error_message: `iCloud inbox is not readable: ${inboxPath}`,
    });
    return;
  }

  let reconcileInFlight = false;
  const runReconcile = (): void => {
    if (reconcileInFlight) return;
    reconcileInFlight = true;
    reconcileIcloudInbox()
      .catch(() => {})
      .finally(() => {
        reconcileInFlight = false;
      });
  };

  runReconcile();
  setInterval(runReconcile, 10_000);

  try {
    watch(inboxPath, { persistent: false }, (_eventType, filename) => {
      if (!filename || !filename.endsWith(".manifest.json")) return;
      runReconcile();
    });

    logEvent({
      event_name: "icloud_watch_started",
      severity: "INFO",
      service: "broker",
      environment: env.NODE_ENV,
      stage: "INGEST",
    });
  } catch {
    logEvent({
      event_name: "icloud_watch_unavailable",
      severity: "WARN",
      service: "broker",
      environment: env.NODE_ENV,
      source: "BROKER",
      stage: "INGEST",
      retriable: true,
      error_message: `fs.watch unavailable for inbox: ${inboxPath}`,
    });
  }
}
