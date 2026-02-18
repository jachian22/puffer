import { expect, test } from "bun:test";

import { createRequest, loadBroker, poll } from "./helpers";

test("request expires when pending past ttl", async () => {
  const { handleRequest, repo, tokens } = await loadBroker();

  const requestId = await createRequest({
    handleRequest,
    agentToken: tokens.agent,
  });

  repo.expirePendingApprovals("9999-01-01T00:00:00.000Z");

  const result = await poll({
    handleRequest,
    agentToken: tokens.agent,
    requestId,
  });

  expect(result.statusCode).toBe(200);
  expect(result.body.status).toBe("EXPIRED");
  expect(result.body.error_code).toBe("APPROVAL_EXPIRED");
});
