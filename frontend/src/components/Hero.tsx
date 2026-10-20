"use client";

import { ForkCanvas } from "./ForkCanvas";
import { ArrowIcon } from "./Glyphs";
import { useMarkets } from "./Providers";
import { fmtPct } from "@/lib/format";
import { yesChance } from "@/lib/market";

export function Hero({ onCreate }: { onCreate: () => void }) {
  const { markets } = useMarkets();
  const ticker = markets.filter((m) => m.status === "open").slice(0, 6);

  return (
    <section id="top" className="relative isolate flex min-h-[100svh] flex-col overflow-hidden">
      <div className="absolute inset-0 -z-10">
        <ForkCanvas />
        <div className="pointer-events-none absolute inset-0 bg-[radial-gradient(ellipse_at_20%_40%,transparent_0%,rgba(6,6,8,0.55)_55%,#060608_100%)]" />
        <div className="pointer-events-none absolute inset-x-0 bottom-0 h-48 bg-gradient-to-b from-transparent to-bg" />
      </div>

      {/* World labels sit on the branches. */}
      <div className="pointer-events-none absolute right-6 top-[17%] hidden text-right lg:block">
        <p className="eyebrow !text-sun/80">World A</p>
        <p className="font-display text-3xl italic text-sun">it happens</p>
      </div>
      <div className="pointer-events-none absolute bottom-[14%] right-6 hidden text-right lg:block">
        <p className="eyebrow !text-moon/80">World B</p>
        <p className="font-display text-3xl italic text-moon">it doesn&apos;t</p>
      </div>

      <div className="mx-auto flex w-full max-w-7xl flex-1 flex-col justify-center px-4 pb-28 pt-28 sm:px-6">
        <div className="max-w-3xl">
          <div className="animate-rise flex flex-wrap items-center gap-2" style={{ animationDelay: "0.05s" }}>
            <span className="chip">
              <span className="h-1.5 w-1.5 animate-pulse-slow rounded-full bg-good" /> Settled by the IMD oracle
            </span>
            <span className="chip">Robinhood Chain</span>
          </div>
          <h1
            className="animate-rise mt-7 font-display text-[clamp(3.2rem,9vw,7.6rem)] leading-[0.92] tracking-[-0.02em]"
            style={{ animationDelay: "0.15s" }}
          >
            Trade the world
            <br />
            <em className="text-split-grad pr-2">where it happens.</em>
          </h1>
          <p
            className="animate-rise mt-7 max-w-xl text-lg leading-relaxed text-ink-2 sm:text-xl"
            style={{ animationDelay: "0.3s" }}
          >
            Conditional markets in IMD. Price what an outcome is worth <span className="text-sun">if</span> an event
            happens, and <span className="text-moon">if it doesn&apos;t</span>. The world that doesn&apos;t happen is
            refunded. Every fee burns IMD.
          </p>
          <div className="animate-rise mt-10 flex flex-wrap gap-3" style={{ animationDelay: "0.45s" }}>
            <a href="#markets" className="btn btn-primary">
              Enter the markets <ArrowIcon className="h-4 w-4" />
            </a>
            <button onClick={onCreate} className="btn btn-ghost">
              Create a market
            </button>
          </div>
        </div>
      </div>

      {ticker.length > 0 && (
        <div className="relative border-y border-line bg-bg/60 backdrop-blur-md">
          <div className="flex w-max animate-marquee gap-10 py-3.5 pl-10">
            {[...ticker, ...ticker].map((m, i) => (
              <a key={`${m.id}-${i}`} href={`#m-${m.id}`} className="flex items-center gap-3 text-sm text-ink-2 hover:text-ink">
                <span className="text-mute">If</span>
                <span className="max-w-[22rem] truncate">{m.condition}</span>
                <span className="num text-sun">{fmtPct(yesChance(m, 0))}</span>
                <span className="text-dim">/</span>
                <span className="num text-moon">{fmtPct(yesChance(m, 1))}</span>
              </a>
            ))}
          </div>
        </div>
      )}
    </section>
  );
}
