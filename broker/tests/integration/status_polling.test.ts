import { expect, test } from "bun:test";

import { handleRequest } from "../../src/server";
import {
  ensureMigrated,
  resetDb,
  TEST_AGENT_TOKEN,
  TEST_PHONE_TOKEN,
} from "../testUtils";

ensureMigrated();

test("GET /v1/request/:id returns 202 while non-terminal", async () => {
  resetDb();
  const create = await handleRequest(
    new Request("http://localhost/v1/request", {
      method: "POST",
      headers: {
        authorization: `Bearer ${TEST_AGENT_TOKEN}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({ type: "statement", month: 5, year: 2026 }),
    })
  );

  const createBody = (await create.json()) as Record<string, unknown>;
  const requestId = String(createBody.request_id);

  const poll = await handleRequest(
    new Request(`http://localhost/v1/request/${requestId}`, {
      headers: { authorization: `Bearer ${TEST_AGENT_TOKEN}` },
    })
  );

  expect(poll.status).toBe(202);
});

test("GET /v1/request/:id returns 200 after denial", async () => {
  resetDb();
  const create = await handleRequest(
    new Request("http://localhost/v1/request", {
      method: "POST",
      headers: {
        authorization: `Bearer ${TEST_AGENT_TOKEN}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({ type: "statement", month: 6, year: 2026 }),
    })
  );

  const createBody = (await create.json()) as Record<string, unknown>;
  const requestId = String(createBody.request_id);

  await handleRequest(
    new Request(`http://localhost/v1/phone/requests/${requestId}/decision`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${TEST_PHONE_TOKEN}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({ decision: "DENY" }),
    })
  );

  const poll = await handleRequest(
    new Request(`http://localhost/v1/request/${requestId}`, {
      headers: { authorization: `Bearer ${TEST_AGENT_TOKEN}` },
    })
  );

  expect(poll.status).toBe(200);
  const payload = (await poll.json()) as Record<string, unknown>;
  expect(payload.status).toBe("DENIED");
});
