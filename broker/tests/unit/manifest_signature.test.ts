import { describe, expect, test } from "bun:test";

import { signPayload } from "../../src/crypto/hmac";
import { env } from "../../src/env";
import { verifyManifest } from "../../src/requests/manifest";

describe("manifest signatures", () => {
  test("verifies a valid signed manifest", async () => {
    const payload = {
      version: "1" as const,
      request_id: "req",
      filename: "req-jan-2026.pdf",
      sha256: "abc",
      bytes: 123,
      completed_at: new Date().toISOString(),
      nonce: "n1",
    };
    const signature = await signPayload(payload, env.BROKER_PHONE_SHARED_SECRET);
    const manifest = { ...payload, signature };

    await expect(verifyManifest(manifest)).resolves.toBe(true);
  });

  test("rejects tampered manifest", async () => {
    const payload = {
      version: "1" as const,
      request_id: "req2",
      filename: "req2-jan-2026.pdf",
      sha256: "abc",
      bytes: 123,
      completed_at: new Date().toISOString(),
      nonce: "n2",
    };
    const signature = await signPayload(payload, env.BROKER_PHONE_SHARED_SECRET);
    const manifest = { ...payload, signature, sha256: "different" };

    await expect(verifyManifest(manifest)).resolves.toBe(false);
  });
});
