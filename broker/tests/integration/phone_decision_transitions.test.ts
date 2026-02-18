import { expect, test } from "bun:test";

import { handleRequest } from "../../src/server";
import {
  ensureMigrated,
  resetDb,
  TEST_AGENT_TOKEN,
  TEST_PHONE_TOKEN,
} from "../testUtils";

ensureMigrated();

test("approve transitions request to EXECUTING", async () => {
  resetDb();

  const create = await handleRequest(
    new Request("http://localhost/v1/request", {
      method: "POST",
      headers: {
        authorization: `Bearer ${TEST_AGENT_TOKEN}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({ type: "statement", month: 3, year: 2026 }),
    })
  );
  const createBody = (await create.json()) as Record<string, unknown>;
  const requestId = String(createBody.request_id);

  const approve = await handleRequest(
    new Request(`http://localhost/v1/phone/requests/${requestId}/decision`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${TEST_PHONE_TOKEN}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({ decision: "APPROVE" }),
    })
  );

  expect(approve.status).toBe(200);
  const approveBody = (await approve.json()) as Record<string, unknown>;
  expect(approveBody.status).toBe("EXECUTING");
});

test("deny transitions request to DENIED", async () => {
  resetDb();

  const create = await handleRequest(
    new Request("http://localhost/v1/request", {
      method: "POST",
      headers: {
        authorization: `Bearer ${TEST_AGENT_TOKEN}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({ type: "statement", month: 4, year: 2026 }),
    })
  );
  const createBody = (await create.json()) as Record<string, unknown>;
  const requestId = String(createBody.request_id);

  const deny = await handleRequest(
    new Request(`http://localhost/v1/phone/requests/${requestId}/decision`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${TEST_PHONE_TOKEN}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({ decision: "DENY" }),
    })
  );

  expect(deny.status).toBe(200);
  const denyBody = (await deny.json()) as Record<string, unknown>;
  expect(denyBody.status).toBe("DENIED");
});
