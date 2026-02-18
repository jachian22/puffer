import { expect, test } from "bun:test";

import { handleRequest } from "../../src/server";
import { ensureMigrated, resetDb, TEST_AGENT_TOKEN } from "../testUtils";

ensureMigrated();

test("POST /v1/request creates pending request", async () => {
  resetDb();
  const res = await handleRequest(
    new Request("http://localhost/v1/request", {
      method: "POST",
      headers: {
        authorization: `Bearer ${TEST_AGENT_TOKEN}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({ type: "statement", month: 1, year: 2026 }),
    })
  );

  expect(res.status).toBe(202);
  const json = (await res.json()) as Record<string, unknown>;
  expect(json.status).toBe("PENDING_APPROVAL");
  expect(typeof json.request_id).toBe("string");
});

test("POST /v1/request idempotency returns same request", async () => {
  resetDb();
  const payload = {
    type: "statement",
    month: 1,
    year: 2026,
    idempotency_key: "abc",
  };

  const res1 = await handleRequest(
    new Request("http://localhost/v1/request", {
      method: "POST",
      headers: {
        authorization: `Bearer ${TEST_AGENT_TOKEN}`,
        "content-type": "application/json",
      },
      body: JSON.stringify(payload),
    })
  );

  const json1 = (await res1.json()) as Record<string, unknown>;

  const res2 = await handleRequest(
    new Request("http://localhost/v1/request", {
      method: "POST",
      headers: {
        authorization: `Bearer ${TEST_AGENT_TOKEN}`,
        "content-type": "application/json",
      },
      body: JSON.stringify(payload),
    })
  );

  const json2 = (await res2.json()) as Record<string, unknown>;
  expect(json2.request_id).toBe(json1.request_id);
});

test("POST /v1/request rejects idempotency key reuse with different payload", async () => {
  resetDb();

  const res1 = await handleRequest(
    new Request("http://localhost/v1/request", {
      method: "POST",
      headers: {
        authorization: `Bearer ${TEST_AGENT_TOKEN}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        type: "statement",
        month: 1,
        year: 2026,
        idempotency_key: "same-key",
      }),
    })
  );

  expect(res1.status).toBe(202);

  const res2 = await handleRequest(
    new Request("http://localhost/v1/request", {
      method: "POST",
      headers: {
        authorization: `Bearer ${TEST_AGENT_TOKEN}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        type: "statement",
        month: 2,
        year: 2026,
        idempotency_key: "same-key",
      }),
    })
  );

  expect(res2.status).toBe(409);
  const json = (await res2.json()) as Record<string, unknown>;
  expect(json.error_code).toBe("IDEMPOTENCY_CONFLICT");
});
