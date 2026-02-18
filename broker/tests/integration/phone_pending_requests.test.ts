import { expect, test } from "bun:test";

import { handleRequest } from "../../src/server";
import {
  ensureMigrated,
  resetDb,
  TEST_AGENT_TOKEN,
  TEST_PHONE_TOKEN,
} from "../testUtils";

ensureMigrated();

test("phone pending endpoint returns signed envelopes", async () => {
  resetDb();

  await handleRequest(
    new Request("http://localhost/v1/request", {
      method: "POST",
      headers: {
        authorization: `Bearer ${TEST_AGENT_TOKEN}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({ type: "statement", month: 2, year: 2026 }),
    })
  );

  const pendingRes = await handleRequest(
    new Request("http://localhost/v1/phone/requests/pending", {
      headers: { authorization: `Bearer ${TEST_PHONE_TOKEN}` },
    })
  );

  expect(pendingRes.status).toBe(200);
  const body = (await pendingRes.json()) as {
    requests: Array<{ envelope: Record<string, unknown> }>;
  };
  expect(body.requests.length).toBe(1);
  expect(body.requests[0]?.envelope?.request_id).toBeDefined();
  expect(body.requests[0]?.envelope?.signature).toBeDefined();
});
