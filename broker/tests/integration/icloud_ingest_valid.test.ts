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

test("reconcile marks request completed for valid manifest", async () => {
  resetDb();
  const dir = await setupTempInbox("ingest-valid");

  try {
    const requestId = await createRequest();
    await approveRequest(requestId);
    await writeSignedManifest({ dir, requestId });

    await reconcileIcloudInbox();

    const row = findById({ requestId });
    expect(row?.status).toBe("COMPLETED");
    expect(row?.result_file_path).toContain(requestId);
  } finally {
    await cleanupTempInbox(dir);
  }
});
