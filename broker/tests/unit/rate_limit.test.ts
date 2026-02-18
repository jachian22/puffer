import { describe, expect, test } from "bun:test";

import { allowRate } from "../../src/util/rateLimit";

describe("rate limiter", () => {
  test("allows requests under threshold", () => {
    for (let i = 0; i < 5; i += 1) {
      expect(
        allowRate({ identity: "a", perTokenPerMinute: 10, globalPerMinute: 100 })
      ).toBe(true);
    }
  });
});
