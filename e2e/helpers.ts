import { mkdir, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";

const shared = {
  initialized: false,
};

function ensureEnv(): void {
  if (shared.initialized) return;
  process.env.NODE_ENV = "test";
  process.env.BROKER_API_TOKEN = "test_broker_api_token";
  process.env.PHONE_API_TOKEN = "test_phone_api_token";
  process.env.BROKER_PHONE_SHARED_SECRET = "test_shared_secret";
  process.env.BROKER_DB_PATH = `/tmp/puffer-e2e-${Date.now()}.sqlite3`;
  process.env.BROKER_HOST = "127.0.0.1";
  process.env.BROKER_PORT = "8765";
  shared.initialized = true;
}

export async function loadBroker() {
  ensureEnv();
  const [{ handleRequest }, repo, ingest, crypto, utils] = await Promise.all([
    import("../broker/src/server"),
    import("../broker/src/requests/repo"),
    import("../broker/src/icloud/ingest"),
    import("../broker/src/crypto/hmac"),
    import("../broker/tests/testUtils"),
  ]);

  utils.ensureMigrated();
  utils.resetDb();

  return {
    handleRequest,
    repo,
    ingest,
    crypto,
    tokens: {
      agent: utils.TEST_AGENT_TOKEN,
      phone: utils.TEST_PHONE_TOKEN,
    },
  };
}

export async function createRequest(params: {
  handleRequest: (req: Request) => Promise<Response>;
  agentToken: string;
  month?: number;
  year?: number;
  idempotencyKey?: string;
}): Promise<string> {
  const res = await params.handleRequest(
    new Request("http://localhost/v1/request", {
      method: "POST",
      headers: {
        authorization: `Bearer ${params.agentToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        type: "statement",
        month: params.month ?? 1,
        year: params.year ?? 2026,
        ...(params.idempotencyKey ? { idempotency_key: params.idempotencyKey } : {}),
      }),
    })
  );

  const json = (await res.json()) as Record<string, unknown>;
  return String(json.request_id);
}

export async function approve(params: {
  handleRequest: (req: Request) => Promise<Response>;
  phoneToken: string;
  requestId: string;
}): Promise<void> {
  await params.handleRequest(
    new Request(`http://localhost/v1/phone/requests/${params.requestId}/decision`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${params.phoneToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({ decision: "APPROVE" }),
    })
  );
}

export async function deny(params: {
  handleRequest: (req: Request) => Promise<Response>;
  phoneToken: string;
  requestId: string;
}): Promise<void> {
  await params.handleRequest(
    new Request(`http://localhost/v1/phone/requests/${params.requestId}/decision`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${params.phoneToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({ decision: "DENY" }),
    })
  );
}

export async function poll(params: {
  handleRequest: (req: Request) => Promise<Response>;
  agentToken: string;
  requestId: string;
}): Promise<{ statusCode: number; body: Record<string, unknown> }> {
  const res = await params.handleRequest(
    new Request(`http://localhost/v1/request/${params.requestId}`, {
      headers: { authorization: `Bearer ${params.agentToken}` },
    })
  );
  return {
    statusCode: res.status,
    body: (await res.json()) as Record<string, unknown>,
  };
}

export async function setupInbox(name: string): Promise<string> {
  const dir = `/tmp/puffer-e2e-inbox-${name}-${Date.now()}`;
  await mkdir(dir, { recursive: true });
  process.env.ICLOUD_INBOX_PATH = dir;

  const { env } = await import("../broker/src/env");
  env.ICLOUD_INBOX_PATH = dir;

  return dir;
}

export async function cleanupInbox(dir: string): Promise<void> {
  await rm(dir, { recursive: true, force: true });
}

export async function writeManifest(params: {
  dir: string;
  requestId: string;
  tamperSignature?: boolean;
}): Promise<void> {
  const { signPayload, sha256HexFromBytes } = await import("../broker/src/crypto/hmac");
  const { env } = await import("../broker/src/env");

  const filename = `${params.requestId}-jan-2026.pdf`;
  const pdfBytes = new TextEncoder().encode("pdf-content");
  const pdfPath = join(params.dir, filename);
  await writeFile(pdfPath, pdfBytes);
  const sha = await sha256HexFromBytes(pdfBytes);

  const unsigned = {
    version: "1" as const,
    request_id: params.requestId,
    filename,
    sha256: sha,
    bytes: pdfBytes.byteLength,
    completed_at: new Date().toISOString(),
    nonce: `${params.requestId}-nonce`,
  };

  const signature = await signPayload(unsigned, env.BROKER_PHONE_SHARED_SECRET);
  const manifest = {
    ...unsigned,
    signature: params.tamperSignature ? `${signature}x` : signature,
  };

  await writeFile(join(params.dir, `${params.requestId}.manifest.json`), JSON.stringify(manifest));
}
