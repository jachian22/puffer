import { expect, test } from "bun:test";

import {
  approve,
  cleanupInbox,
  createRequest,
  loadBroker,
  poll,
  setupInbox,
  writeManifest,
} from "./helpers";

test("request to completion flow", async () => {
  const { handleRequest, ingest, tokens } = await loadBroker();
  const inbox = await setupInbox("completion");

  try {
    const requestId = await createRequest({
      handleRequest,
      agentToken: tokens.agent,
    });

    await approve({
      handleRequest,
      phoneToken: tokens.phone,
      requestId,
    });

    await writeManifest({ dir: inbox, requestId });
    await ingest.reconcileIcloudInbox();

    const result = await poll({
      handleRequest,
      agentToken: tokens.agent,
      requestId,
    });

    expect(result.statusCode).toBe(200);
    expect(result.body.status).toBe("COMPLETED");
    expect(result.body.file_path).toBeDefined();
  } finally {
    await cleanupInbox(inbox);
  }
});
