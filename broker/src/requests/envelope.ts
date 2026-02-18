import { env } from "../env";
import { randomNonceHex, signPayload, verifyPayloadSignature } from "../crypto/hmac";
import { addMinutesIso, nowIso } from "../util/time";

export type SignedRequestEnvelope = {
  version: "1";
  request_id: string;
  type: "statement";
  bank_id: "default";
  params: { month: number; year: number };
  issued_at: string;
  approval_expires_at: string;
  nonce: string;
  signature: string;
};

export async function buildSignedEnvelope(params: {
  requestId: string;
  month: number;
  year: number;
  approvalTtlMinutes: number;
}): Promise<SignedRequestEnvelope> {
  const issuedAt = nowIso();
  const unsigned = {
    version: "1" as const,
    request_id: params.requestId,
    type: "statement" as const,
    bank_id: "default" as const,
    params: { month: params.month, year: params.year },
    issued_at: issuedAt,
    approval_expires_at: addMinutesIso(issuedAt, params.approvalTtlMinutes),
    nonce: randomNonceHex(16),
  };

  const signature = await signPayload(unsigned, env.BROKER_PHONE_SHARED_SECRET);
  return { ...unsigned, signature };
}

export async function verifyEnvelope(
  envelope: SignedRequestEnvelope
): Promise<boolean> {
  const { signature, ...payload } = envelope;
  return verifyPayloadSignature({
    payload,
    signature,
    secret: env.BROKER_PHONE_SHARED_SECRET,
  });
}
