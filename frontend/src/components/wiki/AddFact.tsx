"use client";

import { useState } from "react";

import { useFacts } from "../Providers";
import { FACT_RULES } from "@/lib/config";
import { seedFor, slugify } from "@/lib/facts";
import { fmtImd } from "@/lib/format";

const PLAIN = /^[\x20-\x7e]*$/;
const clean = (v: string) => !v.includes('"') && !v.includes("\\") && PLAIN.test(v);

type Check = { state: "idle" | "checking" | "ok" | "blocked" | "error"; detail?: string };

/** Adds a fact to a page, or starts a page when `topic` is not given. Runs the oracle's free pre-check first. */
export function AddFact({ topic: fixedTopic, onAdded }: { topic?: string; onAdded?: (slug: string, id?: number) => void }) {
  const src = useFacts();
  const [topic, setTopic] = useState(fixedTopic ?? "");
  const [claim, setClaim] = useState("");
  const [rules, setRules] = useState("");
  const [b, setB] = useState("1");
  const [check, setCheck] = useState<Check>({ state: "idle" });

  const liquidity = Number(b);
  const problems = [
    !topic.trim() && "Name the page.",
    topic.length > FACT_RULES.maxTopic && `Page names are up to ${FACT_RULES.maxTopic} characters.`,
    claim.trim().length < 10 && "Write the fact as one statement.",
    claim.length > FACT_RULES.maxClaim && `Facts are up to ${FACT_RULES.maxClaim} characters.`,
    !rules.includes(" ") && "Say how the swarm should judge it, and from which sources.",
    rules.length > FACT_RULES.maxRules && `Rules are up to ${FACT_RULES.maxRules} characters.`,
    ![topic, claim, rules].every(clean) && 'Use plain characters, without " or \\.',
    !(liquidity >= FACT_RULES.minB && liquidity <= FACT_RULES.maxB) && `Depth is ${FACT_RULES.minB} to ${FACT_RULES.maxB}.`,
  ].filter(Boolean) as string[];

  async function precheck() {
    setCheck({ state: "checking" });
    const now = Math.floor(Date.now() / 1000);
    const question = `Conditionals encyclopedia fact 1 round 1 on Robinhood Chain contract 0x0000000000000000000000000000000000000001. Was the following statement true as of unix time ${now} (UTC)? Statement: ${claim.trim()}`;
    try {
      const res = await fetch("/api/check", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ question }),
      });
      const data = (await res.json()) as { ok?: boolean; blockers?: { detail: string }[]; error?: string | null };
      if (data.error) return setCheck({ state: "error", detail: data.error });
      if (data.ok) return setCheck({ state: "ok" });
      setCheck({ state: "blocked", detail: data.blockers?.map((x) => x.detail).join(" ") || "The oracle would not answer this." });
    } catch {
      setCheck({ state: "error", detail: "The check did not answer. Try again." });
    }
  }

  async function submit() {
    if (!src.connected) return src.connect();
    const id = await src.actions.create({ topic: topic.trim(), claim: claim.trim(), rules: rules.trim(), b: liquidity });
    if (id !== undefined) {
      onAdded?.(slugify(topic.trim()), id);
      setClaim("");
      setRules("");
      setCheck({ state: "idle" });
    }
  }

  return (
    <div className="panel grid gap-4 p-5 sm:p-6">
      {!fixedTopic && (
        <label className="grid gap-1.5 text-sm text-ink-2">
          Page
          <input className="field" placeholder="e.g. Bitcoin" value={topic} maxLength={FACT_RULES.maxTopic} onChange={(e) => setTopic(e.target.value)} />
        </label>
      )}
      <label className="grid gap-1.5 text-sm text-ink-2">
        Fact
        <textarea
          className="field min-h-20"
          placeholder="One statement that is true or false today, e.g. Bitcoin's block subsidy is 3.125 BTC"
          value={claim}
          maxLength={FACT_RULES.maxClaim}
          onChange={(e) => {
            setClaim(e.target.value);
            setCheck({ state: "idle" });
          }}
        />
      </label>
      <label className="grid gap-1.5 text-sm text-ink-2">
        How to judge it
        <textarea
          className="field min-h-16"
          placeholder="The sources the swarm should use, e.g. Judge by the Bitcoin Core source code."
          value={rules}
          maxLength={FACT_RULES.maxRules}
          onChange={(e) => setRules(e.target.value)}
        />
      </label>
      <label className="flex flex-wrap items-center gap-2 text-sm text-ink-2">
        Market depth
        <input className="field num !w-24 !py-2" inputMode="decimal" value={b} onChange={(e) => setB(e.target.value.replace(/[^0-9.]/g, ""))} />
        <span className="text-mute">
          You seed {fmtImd(seedFor(liquidity || 0), 3)} IMD, the most you can lose, and earn half of every trading fee.
        </span>
      </label>

      {problems.length > 0 && claim && <p className="text-xs text-sun">{problems[0]}</p>}
      {check.state === "ok" && <p className="text-xs text-good">The IMD oracle can answer this.</p>}
      {(check.state === "blocked" || check.state === "error") && <p className="text-xs text-sun">{check.detail}</p>}

      <div className="flex flex-wrap gap-2">
        <button
          disabled={problems.length > 0 || check.state === "checking"}
          onClick={precheck}
          className="btn btn-ghost !py-2 text-sm"
        >
          {check.state === "checking" ? "Checking…" : "Check with the oracle (free)"}
        </button>
        <button
          disabled={problems.length > 0 || check.state !== "ok" || Boolean(src.pending)}
          onClick={submit}
          className="btn btn-primary !py-2 text-sm"
        >
          {src.connected ? "Add fact" : "Connect to add"}
        </button>
      </div>
    </div>
  );
}
