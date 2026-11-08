/**
 * A small client for Upstash Redis over its REST API (free plan, added to the Vercel project from the Marketplace).
 * Reads KV_REST_API_URL / KV_REST_API_TOKEN, which the Vercel integration sets, or the UPSTASH_REDIS_REST_* names.
 * Without them `kvEnabled` is false and callers fall back.
 */

const URL_ = process.env.KV_REST_API_URL ?? process.env.UPSTASH_REDIS_REST_URL;
const TOKEN = process.env.KV_REST_API_TOKEN ?? process.env.UPSTASH_REDIS_REST_TOKEN;

export const kvEnabled = Boolean(URL_ && TOKEN);

type Command = (string | number)[];

/** Runs commands in one round trip and returns each result. Throws if the store is not configured or fails. */
export async function kv(...commands: Command[]): Promise<unknown[]> {
  if (!kvEnabled) throw new Error("storage not configured");
  const res = await fetch(`${URL_}/pipeline`, {
    method: "POST",
    headers: { authorization: `Bearer ${TOKEN}`, "content-type": "application/json" },
    body: JSON.stringify(commands.map((c) => c.map(String))),
    cache: "no-store",
  });
  if (!res.ok) throw new Error(`storage error ${res.status}`);
  const out = (await res.json()) as { result?: unknown; error?: string }[];
  return out.map((r) => {
    if (r.error) throw new Error(r.error);
    return r.result;
  });
}
