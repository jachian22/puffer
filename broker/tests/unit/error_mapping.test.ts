import { expect, test } from "bun:test";

import { handleRequest } from "../../src/server";
import { ensureMigrated, resetDb, TEST_AGENT_TOKEN } from "../testUtils";

ensureMigrated();

test("returns INVALID_REQUEST_TYPE for unsupported request type", async () => {
  resetDb();
  const res = await handleRequest(
    new Request("http://localhost/v1/request", {
      method: "POST",
      headers: {
        authorization: `Bearer ${TEST_AGENT_TOKEN}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({ type: "other", month: 1, year: 2026 }),
    })
  );

  expect(res.status).toBe(400);
  const payload = (await res.json()) as Record<string, unknown>;
  expect(payload.error_code).toBe("INVALID_REQUEST_TYPE");
});
