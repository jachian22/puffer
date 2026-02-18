import { expect, test } from "bun:test";

import { buildSignedEnvelope } from "../../src/requests/envelope";
import { ensureMigrated, resetDb } from "../testUtils";
import { insertRequest } from "../../src/requests/repo";

ensureMigrated();

test("db uniqueness rejects duplicate request nonce", async () => {
  resetDb();
  const envelope = await buildSignedEnvelope({
    requestId: "dup-1",
    month: 1,
    year: 2026,
    approvalTtlMinutes: 5,
  });

  insertRequest({
    id: "dup-1",
    agentIdentity: "agent",
    requestType: "statement",
    parametersJson: JSON.stringify({ month: 1, year: 2026 }),
    nonce: envelope.nonce,
    signedEnvelopeJson: JSON.stringify(envelope),
    approvalExpiresAt: envelope.approval_expires_at,
  });

  expect(() =>
    insertRequest({
      id: "dup-2",
      agentIdentity: "agent",
      requestType: "statement",
      parametersJson: JSON.stringify({ month: 1, year: 2026 }),
      nonce: envelope.nonce,
      signedEnvelopeJson: JSON.stringify(envelope),
      approvalExpiresAt: envelope.approval_expires_at,
    })
  ).toThrow();
});
