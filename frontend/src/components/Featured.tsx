"use client";

import { useMarkets } from "./Providers";
import { StageChip } from "./MarketCard";
import { fmtImd, fmtPct, fmtPts } from "@/lib/format";
import { impact, totalStaked, worldPot, yesChance } from "@/lib/market";
import type { MarketView } from "@/lib/types";

function WorldHalf({ m, w }: { m: MarketView; w: 0 | 1 }) {
  const sun = w === 0;
  const p = yesChance(m, w);
  return (
    <a
      href={`#m-${m.id}`}
      className={`group relative flex flex-col justify-between overflow-hidden p-6 transition duration-500 sm:p-10 ${
        sun ? "sm:items-start" : "sm:items-end sm:text-right"
      }`}
    >
      <div
        className={`pointer-events-none absolute inset-0 opacity-70 transition duration-700 group-hover:opacity-100 ${
          sun
            ? "bg-[radial-gradient(ellipse_at_0%_100%,rgba(255,181,71,0.22),transparent_60%)]"
            : "bg-[radial-gradient(ellipse_at_100%_100%,rgba(125,227,255,0.2),transparent_60%)]"
        }`}
      />
      <div className="relative">
        <p className={`eyebrow ${sun ? "!text-sun" : "!text-moon"}`}>{sun ? "World A · if it happens" : "World B · if it doesn't"}</p>
        <p className="mt-2 text-sm text-ink-2">chance of YES</p>
      </div>
      <p
        className={`relative font-display leading-none tracking-tight ${sun ? "text-sun-grad" : "text-moon-grad"}`}
        style={{ fontSize: "clamp(5rem, 13vw, 10.5rem)" }}
      >
        {fmtPct(p)}
      </p>
      <div className={`relative flex gap-6 text-sm ${sun ? "" : "sm:justify-end"}`}>
        <span>
          <span className="text-mute">YES </span>
          <span className="num">{fmtImd(m.pools[w][0])}</span>
        </span>
        <span>
          <span className="text-mute">NO </span>
          <span className="num">{fmtImd(m.pools[w][1])}</span>
        </span>
        <span>
          <span className="text-mute">pot </span>
          <span className="num">{fmtImd(worldPot(m, w))}</span>
        </span>
      </div>
    </a>
  );
}

export function Featured({ now }: { now: number }) {
  const { markets } = useMarkets();
  const open = markets.filter((m) => m.status === "open" && now < m.closeTime);
  const m = [...open].sort((a, b) => totalStaked(b) - totalStaked(a))[0];
  if (!m) return null;
  const delta = impact(m);

  return (
    <section className="mx-auto mt-24 max-w-7xl px-4 sm:mt-32 sm:px-6">
      <div className="mb-8 flex flex-wrap items-end justify-between gap-4">
        <div>
          <p className="eyebrow">Featured market</p>
          <h2 className="mt-3 max-w-3xl font-display text-4xl leading-[1.05] sm:text-6xl">
            <span className="italic text-mute">If </span>
            {m.condition.replace(/\s+by\s+\d{4}-\d{2}-\d{2}$/, "")}
            <span className="text-mute">,</span>
          </h2>
          <p className="mt-3 max-w-3xl text-lg text-ink-2 sm:text-xl">
            will {m.outcome.charAt(0).toLowerCase() + m.outcome.slice(1)}?
          </p>
        </div>
        <StageChip m={m} now={now} />
      </div>

      <div className="panel relative grid min-h-[26rem] overflow-hidden !rounded-[28px] sm:grid-cols-2">
        <WorldHalf m={m} w={0} />
        <WorldHalf m={m} w={1} />
        {/* The seam between the worlds. */}
        <div className="pointer-events-none absolute inset-y-0 left-1/2 hidden w-px -translate-x-1/2 bg-gradient-to-b from-transparent via-ink/30 to-transparent sm:block" />
        <div className="pointer-events-none absolute left-1/2 top-1/2 hidden -translate-x-1/2 -translate-y-1/2 sm:block">
          <div className="flex flex-col items-center rounded-2xl border border-line-2 bg-bg/80 px-5 py-4 text-center backdrop-blur-xl">
            <span className="eyebrow !text-[0.6rem]">The condition moves it</span>
            <span className="num mt-1 text-3xl">{fmtPts(delta)}</span>
            <span className="text-xs text-mute">points</span>
          </div>
        </div>
      </div>
      <p className="mt-4 text-sm text-mute">
        {fmtImd(totalStaked(m))} IMD staked. Only one world will happen: stakes in the other are refunded in full.
      </p>
    </section>
  );
}
