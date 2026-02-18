import { canonicalStringify } from "../util/canonicalJson";

function toBytes(input: string): Uint8Array {
  return new TextEncoder().encode(input);
}

function asBufferSource(bytes: Uint8Array): BufferSource {
  return bytes as unknown as BufferSource;
}

function toBase64Url(bytes: Uint8Array): string {
  return Buffer.from(bytes)
    .toString("base64")
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");
}

function fromBase64Url(value: string): Uint8Array {
  const base64 = value.replace(/-/g, "+").replace(/_/g, "/");
  const padded = base64 + "=".repeat((4 - (base64.length % 4)) % 4);
  return new Uint8Array(Buffer.from(padded, "base64"));
}

async function importHmacKey(secret: string): Promise<CryptoKey> {
  return crypto.subtle.importKey(
    "raw",
    asBufferSource(toBytes(secret)),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign", "verify"]
  );
}

export async function signPayload(
  payload: unknown,
  secret: string
): Promise<string> {
  const key = await importHmacKey(secret);
  const body = toBytes(canonicalStringify(payload));
  const signature = await crypto.subtle.sign("HMAC", key, asBufferSource(body));
  return toBase64Url(new Uint8Array(signature));
}

export async function verifyPayloadSignature(params: {
  payload: unknown;
  signature: string;
  secret: string;
}): Promise<boolean> {
  const key = await importHmacKey(params.secret);
  const body = toBytes(canonicalStringify(params.payload));
  const signature = fromBase64Url(params.signature);
  return crypto.subtle.verify("HMAC", key, asBufferSource(signature), asBufferSource(body));
}

export function randomNonceHex(bytes = 16): string {
  const arr = new Uint8Array(bytes);
  crypto.getRandomValues(arr);
  return Buffer.from(arr).toString("hex");
}

export async function sha256HexFromBytes(bytes: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", asBufferSource(bytes));
  return Buffer.from(digest).toString("hex");
}

export async function sha256HexFromFile(path: string): Promise<string> {
  const file = Bun.file(path);
  const bytes = new Uint8Array(await file.arrayBuffer());
  return sha256HexFromBytes(bytes);
}
