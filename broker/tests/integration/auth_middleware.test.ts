import { expect, test } from "bun:test";

import { handleRequest } from "../../src/server";
import { ensureMigrated, resetDb } from "../testUtils";

ensureMigrated();

test("rejects missing auth tokens", async () => {
  resetDb();
  const res = await handleRequest(
    new Request("http://localhost/v1/request", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ type: "statement", month: 1, year: 2026 }),
    })
  );

  expect(res.status).toBe(401);
  const json = (await res.json()) as Record<string, unknown>;
  expect(json.error_code).toBe("UNAUTHORIZED");
});
