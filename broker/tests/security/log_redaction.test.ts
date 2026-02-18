import { expect, test } from "bun:test";

import { logEvent } from "../../src/logging/logger";

test("logger redacts sensitive fields", () => {
  const writes: string[] = [];
  const original = process.stdout.write;
  process.stdout.write = ((chunk: unknown) => {
    writes.push(String(chunk));
    return true;
  }) as typeof process.stdout.write;

  try {
    logEvent({
      event_name: "test",
      severity: "INFO",
      service: "broker",
      environment: "test",
      api_token: "abc",
      nested: { password: "secret" },
    });
  } finally {
    process.stdout.write = original;
  }

  const out = writes.join("\n");
  expect(out).toContain("[REDACTED]");
  expect(out).not.toContain("abc");
  expect(out).not.toContain("secret");
});
