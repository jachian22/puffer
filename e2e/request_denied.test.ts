import { expect, test } from "bun:test";

import { createRequest, deny, loadBroker, poll } from "./helpers";

test("request denied flow", async () => {
  const { handleRequest, tokens } = await loadBroker();

  const requestId = await createRequest({
    handleRequest,
    agentToken: tokens.agent,
  });

  await deny({
    handleRequest,
    phoneToken: tokens.phone,
    requestId,
  });

  const result = await poll({
    handleRequest,
    agentToken: tokens.agent,
    requestId,
  });

  expect(result.statusCode).toBe(200);
  expect(result.body.status).toBe("DENIED");
});
