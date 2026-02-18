const MAX_BODY_BYTES = 256 * 1024;

export async function readJsonWithLimit<T>(req: Request): Promise<T> {
  const contentLength = req.headers.get("content-length");
  if (contentLength) {
    const numeric = Number(contentLength);
    if (Number.isFinite(numeric) && numeric > MAX_BODY_BYTES) {
      throw new Error("REQUEST_TOO_LARGE");
    }
  }

  const body = await req.arrayBuffer();
  if (body.byteLength > MAX_BODY_BYTES) {
    throw new Error("REQUEST_TOO_LARGE");
  }

  if (body.byteLength === 0) {
    throw new Error("INVALID_JSON");
  }

  try {
    return JSON.parse(Buffer.from(body).toString("utf8")) as T;
  } catch {
    throw new Error("INVALID_JSON");
  }
}

export function json(status: number, payload: unknown): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
    },
  });
}
