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

test("digest mismatch fails request verification", async () => {
  resetDb();
  const dir = await setupTempInbox("ingest-hash-mismatch");

  try {
    const requestId = await createRequest();
    await approveRequest(requestId);
    await writeSignedManifest({ dir, requestId, tamperDigest: true });

    await reconcileIcloudInbox();

    const row = findById({ requestId });
    expect(row?.status).toBe("FAILED");
    expect(row?.error_code).toBe("MANIFEST_VERIFICATION_FAILED");
  } finally {
    await cleanupTempInbox(dir);
  }
});
