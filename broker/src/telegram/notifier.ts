import { env } from "../env";
import { logEvent } from "../logging/logger";

function enabled(): boolean {
  return Boolean(env.TELEGRAM_BOT_TOKEN && env.TELEGRAM_PHONE_CHAT_ID);
}

function apiUrl(method: string): string {
  return `https://api.telegram.org/bot${env.TELEGRAM_BOT_TOKEN}/${method}`;
}

export function buildPendingNudgeText(params: {
  requestId: string;
  month: number;
  year: number;
}): string {
  const monthNames = [
    "January",
    "February",
    "March",
    "April",
    "May",
    "June",
    "July",
    "August",
    "September",
    "October",
    "November",
    "December",
  ];
  const monthLabel = monthNames[params.month - 1] ?? String(params.month);
  return [
    "🐡 Statement Request",
    "",
    "Bank: Default",
    `Period: ${monthLabel} ${params.year}`,
    `Request ID: ${params.requestId}`,
    "",
    "Open Secure Data Fetcher on iPhone to approve.",
  ].join("\n");
}

export async function sendTelegramNudge(params: {
  requestId: string;
  month: number;
  year: number;
}): Promise<void> {
  if (!enabled()) return;

  const payload = {
    chat_id: env.TELEGRAM_PHONE_CHAT_ID,
    text: buildPendingNudgeText(params),
  };

  try {
    const res = await fetch(apiUrl("sendMessage"), {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(payload),
    });

    if (!res.ok) {
      logEvent({
        event_name: "telegram_nudge_failed",
        severity: "WARN",
        service: "broker",
        environment: env.NODE_ENV,
        request_id: params.requestId,
        correlation_id: params.requestId,
        status_before: "PENDING_APPROVAL",
        status_after: "PENDING_APPROVAL",
        error_code: "TELEGRAM_ERROR",
        source: "BROKER",
        stage: "APPROVAL",
        retriable: true,
      });
    }
  } catch {
    logEvent({
      event_name: "telegram_nudge_failed",
      severity: "WARN",
      service: "broker",
      environment: env.NODE_ENV,
      request_id: params.requestId,
      correlation_id: params.requestId,
      status_before: "PENDING_APPROVAL",
      status_after: "PENDING_APPROVAL",
      error_code: "TELEGRAM_ERROR",
      source: "BROKER",
      stage: "APPROVAL",
      retriable: true,
    });
  }
}
