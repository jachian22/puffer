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
} from "../integration/helpers";

ensureMigrated();

test("path traversal filename is rejected", async () => {
  resetDb();
  const dir = await setupTempInbox("path-traversal");

  try {
    const requestId = await createRequest();
    await approveRequest(requestId);

    await writeSignedManifest({
      dir,
      requestId,
      filename: "../evil.pdf",
    });

    await reconcileIcloudInbox();

    const row = findById({ requestId });
    expect(row?.status).toBe("FAILED");
    expect(row?.error_code).toBe("MANIFEST_VERIFICATION_FAILED");
  } finally {
    await cleanupTempInbox(dir);
  }
});
