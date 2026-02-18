import { expect, test } from "bun:test";

import { handleRequest } from "../../src/server";
import { findById } from "../../src/requests/repo";
import {
  ensureMigrated,
  resetDb,
  TEST_PHONE_TOKEN,
} from "../testUtils";
import { createRequest } from "./helpers";

ensureMigrated();

test("double approve is race-safe", async () => {
  resetDb();
  const requestId = await createRequest();

  const call = () =>
    handleRequest(
      new Request(`http://localhost/v1/phone/requests/${requestId}/decision`, {
        method: "POST",
        headers: {
          authorization: `Bearer ${TEST_PHONE_TOKEN}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({ decision: "APPROVE" }),
      })
    );

  const [a, b] = await Promise.all([call(), call()]);
  expect([a.status, b.status].sort()).toEqual([200, 200]);

  const aBody = (await a.json()) as Record<string, unknown>;
  const bBody = (await b.json()) as Record<string, unknown>;
  expect([aBody.idempotent, bBody.idempotent].sort()).toEqual([false, true]);

  const row = findById({ requestId });
  expect(row?.status).toBe("EXECUTING");
});
