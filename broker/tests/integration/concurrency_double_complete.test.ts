import { expect, test } from "bun:test";

import { reconcileIcloudInbox } from "../../src/icloud/ingest";
import { findById } from "../../src/requests/repo";
import { ensureMigrated, resetDb } from "../testUtils";
import {
  approveRequest,
  cleanupTempInbox,
  createRequest,
  setupTempInbox,
  writeSignedManifest,
} from "./helpers";

ensureMigrated();

test("duplicate completion manifests do not corrupt terminal state", async () => {
  resetDb();
  const dir = await setupTempInbox("double-complete");

  try {
    const requestId = await createRequest();
    await approveRequest(requestId);
    await writeSignedManifest({ dir, requestId, nonce: `${requestId}-nonce` });
    await reconcileIcloudInbox();

    // Re-write same manifest to simulate duplicate processing.
    await writeSignedManifest({ dir, requestId, nonce: `${requestId}-nonce` });
    await reconcileIcloudInbox();

    const row = findById({ requestId });
    expect(row?.status).toBe("COMPLETED");
  } finally {
    await cleanupTempInbox(dir);
  }
});
