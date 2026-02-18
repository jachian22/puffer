import { describe, expect, test } from "bun:test";

import { canonicalStringify } from "../../src/util/canonicalJson";

describe("canonicalStringify", () => {
  test("sorts nested object keys deterministically", () => {
    const a = canonicalStringify({ b: 2, a: { z: 9, y: 8 } });
    const b = canonicalStringify({ a: { y: 8, z: 9 }, b: 2 });
    expect(a).toBe(b);
  });

  test("preserves array order", () => {
    const out = canonicalStringify({ arr: [{ b: 2, a: 1 }, { c: 3 }] });
    expect(out).toBe('{"arr":[{"a":1,"b":2},{"c":3}]}');
  });
});
