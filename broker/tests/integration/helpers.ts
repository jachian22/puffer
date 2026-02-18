import { mkdir, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";

import { signPayload, sha256HexFromBytes } from "../../src/crypto/hmac";
import { env } from "../../src/env";
import { handleRequest } from "../../src/server";
import {
  TEST_AGENT_TOKEN,
  TEST_PHONE_TOKEN,
} from "../testUtils";

export async function createRequest(month = 1, year = 2026): Promise<string> {
  const res = await handleRequest(
    new Request("http://localhost/v1/request", {
      method: "POST",
      headers: {
        authorization: `Bearer ${TEST_AGENT_TOKEN}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({ type: "statement", month, year }),
    })
  );

  const body = (await res.json()) as Record<string, unknown>;
  return String(body.request_id);
}

export async function approveRequest(requestId: string): Promise<void> {
  await handleRequest(
    new Request(`http://localhost/v1/phone/requests/${requestId}/decision`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${TEST_PHONE_TOKEN}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({ decision: "APPROVE" }),
    })
  );
}

export async function setupTempInbox(name: string): Promise<string> {
  const dir = `/tmp/puffer-${name}-${Date.now()}-${Math.random().toString(16).slice(2)}`;
  await mkdir(dir, { recursive: true });
  env.ICLOUD_INBOX_PATH = dir;
  return dir;
}

export async function cleanupTempInbox(path: string): Promise<void> {
  await rm(path, { recursive: true, force: true });
}

export async function writeSignedManifest(params: {
  dir: string;
  requestId: string;
  filename?: string;
  bytes?: Uint8Array;
  nonce?: string;
  tamperSignature?: boolean;
  tamperDigest?: boolean;
}): Promise<void> {
  const pdfBytes = params.bytes ?? new TextEncoder().encode("pdf-content");
  const filename = params.filename ?? `${params.requestId}-jan-2026.pdf`;
  const pdfPath = join(params.dir, filename);
  await writeFile(pdfPath, pdfBytes);

  const digest = await sha256HexFromBytes(pdfBytes);
  const manifestPayload = {
    version: "1" as const,
    request_id: params.requestId,
    filename,
    sha256: params.tamperDigest ? `${digest}bad` : digest,
    bytes: pdfBytes.byteLength,
    completed_at: new Date().toISOString(),
    nonce: params.nonce ?? `${params.requestId}-nonce`,
  };
  const signature = await signPayload(manifestPayload, env.BROKER_PHONE_SHARED_SECRET);

  const manifest = {
    ...manifestPayload,
    signature: params.tamperSignature ? `${signature}x` : signature,
  };

  const manifestPath = join(params.dir, `${params.requestId}.manifest.json`);
  await writeFile(manifestPath, JSON.stringify(manifest));
}
