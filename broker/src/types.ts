export const REQUEST_STATUSES = [
  "SENT",
  "PENDING_APPROVAL",
  "APPROVED",
  "EXECUTING",
  "COMPLETED",
  "FAILED",
  "DENIED",
  "EXPIRED",
] as const;

export type RequestStatus = (typeof REQUEST_STATUSES)[number];

export type Decision = "APPROVE" | "DENY";

export type ErrorSource = "BROKER" | "PHONE" | "BANK" | "ICLOUD";

export type ErrorStage =
  | "APPROVAL"
  | "AUTH"
  | "NAVIGATION"
  | "DOWNLOAD"
  | "INGEST"
  | "VERIFY";

export type ErrorMeta = {
  error_code: string;
  source: ErrorSource;
  stage: ErrorStage;
  retriable: boolean;
  error_message?: string;
};

export const NON_TERMINAL_STATUSES = new Set<RequestStatus>([
  "SENT",
  "PENDING_APPROVAL",
  "APPROVED",
  "EXECUTING",
]);

export const TERMINAL_STATUSES = new Set<RequestStatus>([
  "COMPLETED",
  "FAILED",
  "DENIED",
  "EXPIRED",
]);
