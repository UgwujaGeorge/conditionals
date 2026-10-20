"use client";

import { ArrowIcon, ForkGlyph } from "./Glyphs";
import { fmtCountdown, fmtImd, fmtPct, fmtPts } from "@/lib/format";
import { impact, STAGE_LABEL, stage, totalStaked, yesChance, type Stage } from "@/lib/market";
import type { MarketView } from "@/lib/types";

export const STAGE_DOT: Record<Stage, string> = {
  trading: "bg-good shadow-[0_0_10px_#6dffb0]",
  closed: "bg-ink-2",
  resolving: "bg-moon shadow-[0_0_10px_#7de3ff] animate-pulse-slow",
  voidable: "bg-burn",
  settled: "bg-sun",
  voided: "bg-dim",
};

export function StageChip({ m, now }: { m: MarketView; now: number }) {
  const s = stage(m, now);
  const time =
    s === "trading" ? `closes in ${fmtCountdown(m.closeTime - now)}` : s === "closed" ? `resolves in ${fmtCountdown(m.resolveTime - now)}` : null;
  return (
    <span className="chip">
      <span className={`h-1.5 w-1.5 rounded-full ${STAGE_DOT[s]}`} />
      {STAGE_LABEL[s]}
      {time && now > 0 && <span className="normal-case tracking-normal text-mute">· {time}</span>}
    </span>
  );
}

export function MarketCard({ m, now }: { m: MarketView; now: number }) {
  const settled = m.status === "settled";
  const delta = impact(m);
  return (
    <a
      href={`#m-${m.id}`}
      className="panel group relative flex flex-col overflow-hidden p-5 transition duration-500 hover:-translate-y-1 hover:border-line-2 sm:p-6"
    >
      <div className="pointer-events-none absolute -right-20 -top-20 h-48 w-48 rounded-full bg-sun/10 opacity-0 blur-3xl transition duration-700 group-hover:opacity-100" />
      <div className="pointer-events-none absolute -bottom-24 -right-10 h-48 w-48 rounded-full bg-moon/10 opacity-0 blur-3xl transition duration-700 group-hover:opacity-100" />
      <div className="flex items-center justify-between gap-2">
        <StageChip m={m} now={now} />
        {m.tag && <span className="eyebrow !text-[0.62rem]">{m.tag}</span>}
      </div>

      <p className="eyebrow mt-5 !text-sun/80">If</p>
      <h3 className="mt-1 line-clamp-2 text-[1.05rem] leading-snug text-ink">{m.condition}</h3>
      <p className="eyebrow mt-4 !text-ink-2/70">Will</p>
      <p className="mt-1 line-clamp-2 text-[0.95rem] leading-snug text-ink-2">{m.outcome}?</p>

      <div className="relative mt-4 -mx-1">
        <ForkGlyph m={m} height={104} settledWorld={settled ? m.world : undefined} />
      </div>

      <div className="mt-2 flex items-end justify-between gap-3 border-t border-line pt-4">
        {settled ? (
          <div>
            <p className="eyebrow !text-[0.6rem]">Result</p>
            <p className="mt-1 text-sm">
              <span className={m.world === 0 ? "text-sun" : "text-moon"}>{m.world === 0 ? "It happened" : "It didn't"}</span>
              <span className="text-mute"> · </span>
              {m.worldRefunded ? "refunded" : m.winningSide === 0 ? "YES won" : "NO won"}
            </p>
          </div>
        ) : (
          <div>
            <p className="eyebrow !text-[0.6rem]">Condition moves it</p>
            <p className="num mt-1 text-lg">
              {fmtPts(delta)} <span className="text-xs text-mute">pts</span>
            </p>
          </div>
        )}
        <div className="text-right">
          <p className="eyebrow !text-[0.6rem]">Staked</p>
          <p className="num mt-1 text-sm text-ink-2">{fmtImd(totalStaked(m))} IMD</p>
        </div>
        <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full border border-line text-ink-2 transition group-hover:border-ink/40 group-hover:bg-ink group-hover:text-bg">
          <ArrowIcon className="h-4 w-4" />
        </span>
      </div>
      <span className="sr-only">
        YES if it happens {fmtPct(yesChance(m, 0))}, YES if it doesn&apos;t {fmtPct(yesChance(m, 1))}
      </span>
    </a>
  );
}
