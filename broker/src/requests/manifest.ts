import { env } from "../env";
import { verifyPayloadSignature } from "../crypto/hmac";

export type CompletionManifest = {
  version: "1";
  request_id: string;
  filename: string;
  sha256: string;
  bytes: number;
  completed_at: string;
  nonce: string;
  signature: string;
};

export async function verifyManifest(
  manifest: CompletionManifest
): Promise<boolean> {
  const { signature, ...payload } = manifest;
  return verifyPayloadSignature({
    payload,
    signature,
    secret: env.BROKER_PHONE_SHARED_SECRET,
  });
}
