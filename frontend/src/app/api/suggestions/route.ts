import { createPublicClient, getAddress, http, isAddress, type Hex } from "viem";

import { chain } from "@/lib/config";
import { kv, kvEnabled } from "@/lib/server/kv";
import { createMessage, SUGGEST_LIMITS, voteMessage, type Suggestion, type SuggestionKind } from "@/lib/suggest";

const client = createPublicClient({ chain, transport: http() });
const KINDS: SuggestionKind[] = ["new", "market", "fact"];
/** A signature is accepted for 10 minutes after it was made. */
const FRESH_SECONDS = 600;
/** One new suggestion per wallet per hour. */
const POST_EVERY_SECONDS = 3600;
const TEXT_OK = /^[\x20-\x7e]*$/;

const bad = (error: string, status = 400) => Response.json({ error }, { status });
const off = () => Response.json({ enabled: false, suggestions: [] });

/** The most backed suggestions, with whether `?voter=` has backed each. */
export async function GET(req: Request) {
  if (!kvEnabled) return off();
  const voterParam = new URL(req.url).searchParams.get("voter");
  const voter = voterParam && isAddress(voterParam) ? getAddress(voterParam) : null;
  try {
    const [ranked] = (await kv(["ZREVRANGE", "sug:rank", 0, 99, "WITHSCORES"])) as [string[]];
    const ids: number[] = [];
    const votes = new Map<number, number>();
    for (let i = 0; i < ranked.length; i += 2) {
      const id = Number(ranked[i]);
      ids.push(id);
      votes.set(id, Number(ranked[i + 1]));
    }
    if (!ids.length) return Response.json({ enabled: true, suggestions: [] });
    const results = await kv(
      ["MGET", ...ids.map((id) => `sug:${id}`)],
      ...(voter ? ids.map((id) => ["SISMEMBER", `sug:${id}:v`, voter]) : []),
    );
    const raws = results[0] as (string | null)[];
    const suggestions: Suggestion[] = ids.flatMap((id, i) => {
      const raw = raws[i];
      if (!raw) return [];
      const s = JSON.parse(raw) as Omit<Suggestion, "votes">;
      return [{ ...s, votes: votes.get(id) ?? 0, voted: voter ? Number(results[i + 1]) === 1 : undefined }];
    });
    return Response.json({ enabled: true, suggestions }, { headers: { "cache-control": "no-store" } });
  } catch {
    return bad("Suggestions could not be read. Try again.", 502);
  }
}

type Body = {
  action?: string;
  kind?: string;
  ref?: number | null;
  text?: string;
  id?: number;
  address?: string;
  signature?: string;
  issuedAt?: number;
};

export async function POST(req: Request) {
  if (!kvEnabled) return bad("Suggestions are not open yet.", 503);
  let body: Body;
  try {
    body = (await req.json()) as Body;
  } catch {
    return bad("Bad request.");
  }
  const { address, signature, issuedAt } = body;
  if (!address || !isAddress(address) || typeof signature !== "string" || !signature.startsWith("0x")) {
    return bad("Connect a wallet and sign.");
  }
  const now = Math.floor(Date.now() / 1000);
  if (typeof issuedAt !== "number" || issuedAt > now + 60 || now - issuedAt > FRESH_SECONDS) {
    return bad("That signature has expired. Sign again.");
  }
  const who = getAddress(address);

  let message: string;
  if (body.action === "create") {
    const kind = body.kind as SuggestionKind;
    if (!KINDS.includes(kind)) return bad("Pick what you are suggesting.");
    const text = (body.text ?? "").trim();
    if (text.length > SUGGEST_LIMITS.maxText || !TEXT_OK.test(text)) return bad("Keep it under 280 plain characters.");
    if (kind === "new" && text.length < SUGGEST_LIMITS.minIdea) return bad("Describe the market in a sentence.");
    const ref = kind === "new" ? null : Number(body.ref);
    if (kind !== "new" && (!Number.isInteger(ref) || (ref as number) < 1)) return bad("Give the market or fact number.");
    message = createMessage(kind, ref, text, issuedAt);
    if (!(await verified(who, message, signature as Hex))) return bad("The signature does not match the wallet.", 401);
    try {
      const [fresh] = await kv(["SET", `sug:rl:${who}`, "1", "NX", "EX", POST_EVERY_SECONDS]);
      if (fresh !== "OK") return bad("One suggestion per wallet per hour. Back other suggestions meanwhile.", 429);
      const [id] = (await kv(["INCR", "sug:next"])) as [number];
      const record = { id: Number(id), kind, ref, text, author: who, at: now };
      await kv(["SET", `sug:${id}`, JSON.stringify(record)], ["SADD", `sug:${id}:v`, who], ["ZADD", "sug:rank", 1, id]);
      return Response.json({ ok: true, id: Number(id) });
    } catch {
      return bad("The suggestion could not be saved. Try again.", 502);
    }
  }

  if (body.action === "vote") {
    const id = Number(body.id);
    if (!Number.isInteger(id) || id < 1) return bad("Unknown suggestion.");
    message = voteMessage(id, issuedAt);
    if (!(await verified(who, message, signature as Hex))) return bad("The signature does not match the wallet.", 401);
    try {
      const [exists] = await kv(["EXISTS", `sug:${id}`]);
      if (Number(exists) !== 1) return bad("Unknown suggestion.", 404);
      const [added] = await kv(["SADD", `sug:${id}:v`, who]);
      if (Number(added) === 1) await kv(["ZINCRBY", "sug:rank", 1, id]);
      return Response.json({ ok: true, counted: Number(added) === 1 });
    } catch {
      return bad("The vote could not be saved. Try again.", 502);
    }
  }

  return bad("Unknown action.");
}

/** Checks the signature against the wallet, smart-contract wallets included. */
async function verified(address: `0x${string}`, message: string, signature: Hex) {
  try {
    return await client.verifyMessage({ address, message, signature });
  } catch {
    return false;
  }
}
