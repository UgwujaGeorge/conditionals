"use client";

import { useState } from "react";

import { useFacts } from "../Providers";
import { FACT_RULES } from "@/lib/config";
import { pTrue, quoteBuy, seedFor, stance, type FactSide, type FactView } from "@/lib/facts";
import { fmtImd, fmtPct } from "@/lib/format";

const day = (unix: number) =>
  new Date(unix * 1000).toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric", timeZone: "UTC" });

const STANCE_CLASS: Record<string, string> = {
  established: "text-good",
  likely: "text-good/80",
  disputed: "text-sun",
  doubtful: "text-moon/80",
  rejected: "text-moon",
};

export function chanceShown(f: FactView) {
  if (f.phase === "settled" || f.phase === "closed") return f.verdict === 1 ? 1 : f.verdict === 2 ? 0 : 0.5;
  return pTrue(f.q, f.b);
}

/** One fact: its odds, the swarm's verdict, and its market. */
export function FactCard({ fact: f }: { fact: FactView }) {
  const src = useFacts();
  const [open, setOpen] = useState(false);
  const [amount, setAmount] = useState("1");
  const p = chanceShown(f);
  const word = stance(p);
  const trading = f.phase === "open";
  const value = Number(amount);
  const valid = Number.isFinite(value) && value >= FACT_RULES.minTrade;
  const quote = (side: FactSide) => (valid && trading ? quoteBuy(f.q, f.b, side, value) : null);
  const busy = Boolean(src.pending);

  const guard = (fn: () => void) => () => (src.connected ? fn() : src.connect());

  return (
    <article id={`f-${f.id}`} className="panel scroll-mt-24 p-5 sm:p-6">
      <div className="flex items-start gap-5">
        <div className="min-w-0 flex-1">
          <p className="text-[1.05rem] leading-snug text-ink">{f.claim}</p>
          <div className="mt-3 flex flex-wrap items-center gap-2">
            <span className={`chip ${STANCE_CLASS[word]}`}>{word}</span>
            {f.verdict === 1 && <span className="chip !text-good">Swarm: true · {day(f.verdictAt)}</span>}
            {f.verdict === 2 && <span className="chip !text-burn">Swarm: false · {day(f.verdictAt)}</span>}
            {f.verdict === 0 && <span className="chip">Not judged yet</span>}
            {f.phase === "asking" && (
              <span className="chip !text-moon">
                <span className="h-1.5 w-1.5 animate-pulse-slow rounded-full bg-moon" /> Swarm judging
              </span>
            )}
            <span className="chip">Round {f.round}</span>
          </div>
        </div>
        <div className="shrink-0 text-right">
          <p className="num text-3xl leading-none text-ink">{fmtPct(p)}</p>
          <p className="eyebrow mt-1.5 !tracking-[0.14em]">true</p>
        </div>
      </div>

      <div className="mt-4 flex h-1.5 overflow-hidden rounded-full bg-moon/25" aria-hidden>
        <div className="bg-gradient-to-r from-sun-2 to-sun transition-all duration-700" style={{ width: `${p * 100}%` }} />
      </div>

      {f.redeemable.length > 0 && (
        <div className="mt-4 flex flex-wrap gap-2">
          {f.redeemable.map((r) => (
            <button key={r.round} disabled={busy} onClick={() => src.actions.redeem(f.id, r.round)} className="btn btn-primary !py-2 text-sm">
              Redeem {fmtImd(r.amount)} IMD · round {r.round}
            </button>
          ))}
        </div>
      )}

      <div className="mt-4 flex flex-wrap items-center gap-2 text-sm">
        {trading && (
          <button onClick={() => setOpen((o) => !o)} className="btn btn-ghost !py-1.5 text-sm">
            {open ? "Close" : "Trade"}
          </button>
        )}
        {trading && (
          <button
            disabled={busy}
            onClick={guard(() => src.actions.challenge(f.id))}
            className="btn btn-ghost !py-1.5 text-sm"
            title="Pay the IMD oracle to judge this fact now. The round pays the side the swarm picks."
          >
            Ask the swarm · {FACT_RULES.oraclePrice} IMD
          </button>
        )}
        {(f.phase === "settled" || f.phase === "closed") && (
          <button disabled={busy} onClick={guard(() => src.actions.openRound(f.id))} className="btn btn-ghost !py-1.5 text-sm">
            Open round {f.round + 1} · seed {fmtImd(seedFor(f.b), 3)} IMD
          </button>
        )}
        {f.phase === "asking" && <span className="text-mute">Trading resumes when the swarm answers.</span>}
        {f.phase === "asking" && src.actions.simulateVerdict && (
          <>
            <button onClick={() => src.actions.simulateVerdict!(f.id, true)} className="btn btn-ghost !py-1.5 text-sm">
              Sample: answer true
            </button>
            <button onClick={() => src.actions.simulateVerdict!(f.id, false)} className="btn btn-ghost !py-1.5 text-sm">
              Sample: answer false
            </button>
          </>
        )}
        <span className="ml-auto text-xs text-dim">
          {fmtImd(f.liquidity)} IMD in market · #{f.id}
        </span>
      </div>

      {open && trading && (
        <div className="mt-4 grid gap-3 border-t border-line pt-4">
          <div className="flex flex-wrap items-center gap-3">
            <label className="flex items-center gap-2 text-sm text-ink-2">
              Amount
              <input
                className="field num !w-28 !py-2"
                inputMode="decimal"
                value={amount}
                onChange={(e) => setAmount(e.target.value.replace(/[^0-9.]/g, ""))}
              />
              IMD
            </label>
            <span className="text-xs text-mute">Balance {fmtImd(src.balance)} IMD</span>
          </div>
          <div className="grid gap-2 sm:grid-cols-2">
            {([0, 1] as FactSide[]).map((side) => {
              const q = quote(side);
              return (
                <button
                  key={side}
                  disabled={!valid || busy || q?.limited}
                  onClick={guard(() => src.actions.buy(f.id, side, value))}
                  className={`btn !justify-between !rounded-2xl border !px-4 !py-3 text-left ${
                    side === 0 ? "border-sun/40 hover:bg-sun/10" : "border-moon/40 hover:bg-moon/10"
                  }`}
                >
                  <span className={side === 0 ? "text-sun" : "text-moon"}>Buy {side === 0 ? "TRUE" : "FALSE"}</span>
                  <span className="num text-xs text-ink-2">{q ? `pays ${fmtImd(q.shares)} IMD if ${side === 0 ? "true" : "false"}` : "—"}</span>
                </button>
              );
            })}
          </div>
          {(f.mine[0] > 0 || f.mine[1] > 0) && (
            <div className="flex flex-wrap items-center gap-2 text-sm text-ink-2">
              You hold
              {([0, 1] as FactSide[]).map((side) =>
                f.mine[side] > 0 ? (
                  <button
                    key={side}
                    disabled={busy}
                    onClick={() => src.actions.sell(f.id, side, f.mine[side])}
                    className="btn btn-ghost !py-1.5 text-sm"
                  >
                    {fmtImd(f.mine[side])} {side === 0 ? "TRUE" : "FALSE"} · sell
                  </button>
                ) : null,
              )}
            </div>
          )}
          <p className="text-xs leading-relaxed text-mute">
            Each share pays 1 IMD if the swarm agrees with it when this fact is next judged. Sell any time before that.
            Rules: {f.rules}
          </p>
        </div>
      )}
    </article>
  );
}
