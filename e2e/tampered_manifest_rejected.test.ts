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

test("tampered manifest is rejected", async () => {
  const { handleRequest, ingest, tokens } = await loadBroker();
  const inbox = await setupInbox("tampered");

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

    await writeManifest({
      dir: inbox,
      requestId,
      tamperSignature: true,
    });

    await ingest.reconcileIcloudInbox();

    const result = await poll({
      handleRequest,
      agentToken: tokens.agent,
      requestId,
    });

    expect(result.statusCode).toBe(200);
    expect(result.body.status).toBe("FAILED");
    expect(result.body.error_code).toBe("MANIFEST_VERIFICATION_FAILED");
  } finally {
    await cleanupInbox(inbox);
  }
});
