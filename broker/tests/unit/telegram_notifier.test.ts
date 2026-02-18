import { expect, test } from "bun:test";

import { buildPendingNudgeText } from "../../src/telegram/notifier";

test("telegram nudge text includes request id and period", () => {
  const text = buildPendingNudgeText({
    requestId: "abc123",
    month: 1,
    year: 2026,
  });

  expect(text).toContain("abc123");
  expect(text).toContain("January 2026");
});
