import { expect, test } from "bun:test";

import { approve, createRequest, loadBroker, poll } from "./helpers";

test("execution timeout maps to FAILED", async () => {
  const { handleRequest, repo, tokens } = await loadBroker();

  const requestId = await createRequest({
    handleRequest,
    agentToken: tokens.agent,
  });

  await approve({
    handleRequest,
    phoneToken: tokens.phone,
    requestId,
  });

  repo.expireExecutionTimeouts("9999-01-01T00:00:00.000Z");

  const result = await poll({
    handleRequest,
    agentToken: tokens.agent,
    requestId,
  });

  expect(result.statusCode).toBe(200);
  expect(result.body.status).toBe("FAILED");
  expect(result.body.error_code).toBe("EXECUTION_TIMEOUT");
});
