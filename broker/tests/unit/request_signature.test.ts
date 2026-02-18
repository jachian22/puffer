import { describe, expect, test } from "bun:test";

import { buildSignedEnvelope, verifyEnvelope } from "../../src/requests/envelope";

describe("request envelope signatures", () => {
  test("verifies valid envelope", async () => {
    const envelope = await buildSignedEnvelope({
      requestId: "r1",
      month: 1,
      year: 2026,
      approvalTtlMinutes: 5,
    });
    await expect(verifyEnvelope(envelope)).resolves.toBe(true);
  });

  test("fails on tampered payload", async () => {
    const envelope = await buildSignedEnvelope({
      requestId: "r2",
      month: 1,
      year: 2026,
      approvalTtlMinutes: 5,
    });
    envelope.params.month = 2;
    await expect(verifyEnvelope(envelope)).resolves.toBe(false);
  });
});
