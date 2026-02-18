import type { RequestStatus } from "../types";

export const ALLOWED_TRANSITIONS = new Set<string>([
  "SENT->PENDING_APPROVAL",
  "PENDING_APPROVAL->APPROVED",
  "PENDING_APPROVAL->DENIED",
  "PENDING_APPROVAL->EXPIRED",
  "APPROVED->EXECUTING",
  "APPROVED->FAILED",
  "EXECUTING->COMPLETED",
  "EXECUTING->FAILED",
]);

export function canTransition(from: RequestStatus, to: RequestStatus): boolean {
  return ALLOWED_TRANSITIONS.has(`${from}->${to}`);
}
