import { describe, expect, test } from "bun:test";

import { canTransition } from "../../src/requests/state";

describe("state machine transitions", () => {
  test("allows expected transitions", () => {
    expect(canTransition("PENDING_APPROVAL", "APPROVED")).toBe(true);
    expect(canTransition("APPROVED", "EXECUTING")).toBe(true);
    expect(canTransition("EXECUTING", "COMPLETED")).toBe(true);
  });

  test("rejects terminal rollback transitions", () => {
    expect(canTransition("COMPLETED", "EXECUTING")).toBe(false);
    expect(canTransition("EXPIRED", "APPROVED")).toBe(false);
  });
});
