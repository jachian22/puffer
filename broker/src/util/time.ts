export function nowIso(): string {
  return new Date().toISOString();
}

export function addMinutesIso(baseIso: string, minutes: number): string {
  return new Date(Date.parse(baseIso) + minutes * 60_000).toISOString();
}

export function addSecondsIso(baseIso: string, seconds: number): string {
  return new Date(Date.parse(baseIso) + seconds * 1_000).toISOString();
}

export function isExpired(iso: string, nowMs = Date.now()): boolean {
  const ts = Date.parse(iso);
  return Number.isFinite(ts) ? nowMs > ts : false;
}
