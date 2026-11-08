import { createPublicClient, formatEther, http, type Address } from "viem";

import { factsAbi } from "@/lib/abi";
import { ADDRESSES, chain } from "@/lib/config";
import { PHASES, phaseOf, pTrue, slugify, type FactView, type Verdict } from "@/lib/facts";
import { demoFacts } from "@/lib/factsDemo";

const client = createPublicClient({ chain, transport: http() });
const n = (v: bigint) => Number(formatEther(v));
const LIMIT = 300;

/** Every fact as the server reads it: from the chain when the contract is live, else the samples. */
export async function loadFacts(): Promise<{ source: "live" | "sample"; facts: FactView[] }> {
  const address = ADDRESSES.facts as Address | undefined;
  if (!address) return { source: "sample", facts: demoFacts() };

  const base = { address, abi: factsAbi } as const;
  const count = Number(await client.readContract({ ...base, functionName: "factCount" }));
  const ids = Array.from({ length: Math.min(count, LIMIT) }, (_, i) => count - i);
  const facts = await Promise.all(
    ids.map(async (id) => {
      const f = await client.readContract({ ...base, functionName: "getFact", args: [BigInt(id)] });
      const r = await client.readContract({ ...base, functionName: "getRound", args: [BigInt(id), f.rounds] });
      const view: FactView = {
        id,
        creator: f.creator,
        topic: f.topic,
        claim: f.claim,
        rules: f.rules,
        b: n(f.b),
        round: f.rounds,
        verdict: f.verdict as Verdict,
        verdictAt: Number(f.verdictAt),
        createdAt: Number(f.createdAt),
        phase: phaseOf(PHASES[r.phase] ?? "none", Number(r.askedAt)),
        askedAt: Number(r.askedAt),
        seeder: r.seeder,
        seed: n(r.seed),
        q: [n(r.q[0]), n(r.q[1])],
        liquidity: n(r.makerBalance),
        mine: [0, 0],
        redeemable: [],
      };
      return view;
    }),
  );
  return { source: "live", facts };
}

/** The chance of TRUE the encyclopedia uses for a fact: the round's price while it trades, else the verdict. */
export function chanceOf(f: FactView) {
  if (f.phase === "settled" || f.phase === "closed") return f.verdict === 1 ? 1 : f.verdict === 2 ? 0 : 0.5;
  return pTrue(f.q, f.b);
}

/** A fact as the public API returns it. */
export function publicFact(f: FactView) {
  return {
    id: f.id,
    topic: f.topic,
    page: `/wiki/${slugify(f.topic)}`,
    claim: f.claim,
    rules: f.rules,
    probabilityTrue: Math.round(chanceOf(f) * 10_000) / 10_000,
    verdict: f.verdict === 1 ? true : f.verdict === 2 ? false : null,
    verdictAsOf: f.verdictAt || null,
    round: f.round,
    phase: f.phase,
    liquidityImd: Math.round(f.liquidity * 1e4) / 1e4,
  };
}
