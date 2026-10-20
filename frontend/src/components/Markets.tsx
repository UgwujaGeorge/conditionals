"use client";

import { useMemo, useState } from "react";

import { MarketCard } from "./MarketCard";
import { useMarkets } from "./Providers";
import { stage, totalStaked } from "@/lib/market";

const FILTERS = [
  { id: "all", label: "All" },
  { id: "live", label: "Live" },
  { id: "resolving", label: "Resolving" },
  { id: "done", label: "Settled" },
  { id: "mine", label: "My positions" },
] as const;

type Filter = (typeof FILTERS)[number]["id"];

export function Markets({ now, onCreate }: { now: number; onCreate: () => void }) {
  const { markets, ready, live } = useMarkets();
  const [filter, setFilter] = useState<Filter>("all");

  const shown = useMemo(() => {
    const list = markets.filter((m) => {
      const s = stage(m, now);
      if (filter === "live") return s === "trading";
      if (filter === "resolving") return s === "closed" || s === "resolving" || s === "voidable";
      if (filter === "done") return s === "settled" || s === "voided";
      if (filter === "mine") return m.mine.flat().some((v) => v > 0) || m.claimable > 0;
      return true;
    });
    const rank = (s: string) => (s === "trading" ? 0 : s === "resolving" || s === "voidable" ? 1 : s === "closed" ? 2 : 3);
    return list.sort((a, b) => rank(stage(a, now)) - rank(stage(b, now)) || totalStaked(b) - totalStaked(a));
  }, [markets, filter, now]);

  return (
    <section id="markets" className="mx-auto mt-28 max-w-7xl scroll-mt-20 px-4 sm:mt-36 sm:px-6">
      <div className="flex flex-wrap items-end justify-between gap-6">
        <div>
          <p className="eyebrow">Markets</p>
          <h2 className="mt-3 font-display text-5xl leading-none sm:text-7xl">
            Every question, <em className="text-split-grad">twice.</em>
          </h2>
          <p className="mt-4 max-w-xl text-ink-2">
            Each market splits into two worlds. The percentages are the chance of YES in each one: the gap between them
            is what the crowd thinks the condition does.
          </p>
        </div>
        <div className="flex gap-1 overflow-x-auto rounded-full border border-line bg-bg-2/80 p-1 scrollbar-none">
          {FILTERS.map((f) => (
            <button
              key={f.id}
              onClick={() => setFilter(f.id)}
              className={`whitespace-nowrap rounded-full px-4 py-2 text-sm transition ${
                filter === f.id ? "bg-ink text-bg" : "text-ink-2 hover:text-ink"
              }`}
            >
              {f.label}
            </button>
          ))}
        </div>
      </div>

      <div className="mt-10 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {shown.map((m) => (
          <MarketCard key={m.id} m={m} now={now} />
        ))}
        {ready && shown.length === 0 && (
          <div className="panel col-span-full flex flex-col items-center gap-4 p-14 text-center">
            <p className="font-display text-3xl">
              {filter === "mine" ? "No positions yet." : live && markets.length === 0 ? "The first world is yours." : "Nothing here."}
            </p>
            <p className="max-w-md text-ink-2">
              {live && markets.length === 0
                ? "No markets yet. Write a condition, an outcome and the sources the oracle should use."
                : "Try another filter, or open a new market."}
            </p>
            <button onClick={onCreate} className="btn btn-primary">
              Create a market
            </button>
          </div>
        )}
        {!ready &&
          Array.from({ length: 6 }).map((_, i) => <div key={i} className="panel h-[25rem] animate-pulse-slow" />)}
      </div>
    </section>
  );
}
