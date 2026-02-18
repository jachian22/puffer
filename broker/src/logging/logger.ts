import { nowIso } from "../util/time";

export type LogLevel = "ERROR" | "WARN" | "INFO" | "DEBUG";

export type LogEvent = {
  timestamp?: string;
  event_name: string;
  severity: LogLevel;
  service: "broker" | "iphone";
  environment: string;
  request_id?: string;
  correlation_id?: string;
  status_before?: string;
  status_after?: string;
  duration_ms?: number;
  [key: string]: unknown;
};

const REDACT_PATTERNS = [
  /token/i,
  /secret/i,
  /password/i,
  /authorization/i,
  /cookie/i,
  /credential/i,
];

function redactValue(key: string, value: unknown): unknown {
  if (REDACT_PATTERNS.some((pattern) => pattern.test(key))) {
    return "[REDACTED]";
  }
  if (value && typeof value === "object" && !Array.isArray(value)) {
    const out: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(value as Record<string, unknown>)) {
      out[k] = redactValue(k, v);
    }
    return out;
  }
  if (Array.isArray(value)) {
    return value.map((v) => redactValue(key, v));
  }
  return value;
}

function validateShape(event: LogEvent): void {
  const required = ["event_name", "severity", "service", "environment"];
  for (const key of required) {
    if (!(key in event)) {
      throw new Error(`invalid_log_event_missing_${key}`);
    }
  }
}

export function logEvent(event: LogEvent): void {
  validateShape(event);
  const payload: Record<string, unknown> = {
    ...event,
    timestamp: event.timestamp ?? nowIso(),
  };

  const redacted = redactValue("root", payload);
  process.stdout.write(`${JSON.stringify(redacted)}\n`);
}
