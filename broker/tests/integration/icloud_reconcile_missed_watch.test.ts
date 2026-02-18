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

test("reconcile loop completes request without watcher events", async () => {
  resetDb();
  const dir = await setupTempInbox("reconcile-missed-watch");

  try {
    const requestId = await createRequest();
    await approveRequest(requestId);
    await writeSignedManifest({ dir, requestId });

    await reconcileIcloudInbox();

    const row = findById({ requestId });
    expect(row?.status).toBe("COMPLETED");
  } finally {
    await cleanupTempInbox(dir);
  }
});
