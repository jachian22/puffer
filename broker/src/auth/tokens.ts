import { env } from "../env";
import { sha256Hex } from "../crypto/hash";

export type AuthResult =
  | { ok: true; identity: string; tokenType: "agent" | "phone" }
  | { ok: false; status: number; error: string };

function parseBearer(authorization: string | null): string | null {
  if (!authorization) return null;
  const [scheme, token] = authorization.split(" ", 2);
  if (!scheme || !token) return null;
  if (scheme.toLowerCase() !== "bearer") return null;
  return token.trim() || null;
}

export async function authenticateAgent(
  authorization: string | null
): Promise<AuthResult> {
  const token = parseBearer(authorization);
  if (!token) return { ok: false, status: 401, error: "UNAUTHORIZED" };
  if (token !== env.BROKER_API_TOKEN) {
    return { ok: false, status: 401, error: "UNAUTHORIZED" };
  }
  return {
    ok: true,
    identity: await sha256Hex(`agent:${token}`),
    tokenType: "agent",
  };
}

export async function authenticatePhone(
  authorization: string | null
): Promise<AuthResult> {
  const token = parseBearer(authorization);
  if (!token) return { ok: false, status: 401, error: "UNAUTHORIZED" };
  if (token !== env.PHONE_API_TOKEN) {
    return { ok: false, status: 401, error: "UNAUTHORIZED" };
  }
  return {
    ok: true,
    identity: await sha256Hex(`phone:${token}`),
    tokenType: "phone",
  };
}
