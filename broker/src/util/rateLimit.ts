type Bucket = { count: number; windowStartMs: number };

const buckets = new Map<string, Bucket>();

function withinWindow(nowMs: number, startMs: number, windowMs: number): boolean {
  return nowMs - startMs < windowMs;
}

function bump(key: string, limit: number, windowMs: number, nowMs = Date.now()): boolean {
  const current = buckets.get(key);
  if (!current || !withinWindow(nowMs, current.windowStartMs, windowMs)) {
    buckets.set(key, { count: 1, windowStartMs: nowMs });
    return true;
  }

  if (current.count >= limit) {
    return false;
  }

  current.count += 1;
  buckets.set(key, current);
  return true;
}

export function allowRate(params: {
  identity: string;
  perTokenPerMinute: number;
  globalPerMinute: number;
}): boolean {
  const now = Date.now();
  const minute = 60_000;
  const globalOk = bump("global", params.globalPerMinute, minute, now);
  if (!globalOk) return false;
  const tokenOk = bump(
    `identity:${params.identity}`,
    params.perTokenPerMinute,
    minute,
    now
  );
  return tokenOk;
}
