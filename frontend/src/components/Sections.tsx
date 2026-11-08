"use client";

import Link from "next/link";

import { Logo } from "./Glyphs";
import { useMarkets } from "./Providers";
import { LINKS } from "@/lib/config";

const STEPS = [
  {
    n: "01",
    title: "A question forks",
    body: "Anyone opens a market: if CONDITION, will OUTCOME? It splits into World A, where the condition happens, and World B, where it doesn't.",
  },
  {
    n: "02",
    title: "Stake in a world",
    body: "Back YES or NO in either world. The price is live from the first trade and fixed when you enter. You can hold positions in both worlds at once.",
  },
  {
    n: "03",
    title: "The oracle answers",
    body: "After the resolve time the contract pays IMD's oracle for two questions. A panel of agents answers; only a signed answer to the exact question counts.",
  },
  {
    n: "04",
    title: "One world settles",
    body: "The world that didn't happen is refunded. In the one that did, every winning share pays 1 IMD. Sell any time before the close if you change your mind.",
  },
];

export function HowItWorks() {
  return (
    <section id="how" className="mx-auto mt-32 max-w-7xl scroll-mt-20 px-4 sm:mt-44 sm:px-6">
      <p className="eyebrow">How it works</p>
      <h2 className="mt-3 max-w-4xl font-display text-5xl leading-[1.02] sm:text-7xl">
        Prediction markets price <span className="italic text-mute">whether.</span> Conditionals price{" "}
        <em className="text-split-grad">what then.</em>
      </h2>
      <div className="mt-14 grid gap-px overflow-hidden rounded-[22px] border border-line bg-line md:grid-cols-2 lg:grid-cols-4">
        {STEPS.map((s, i) => (
          <div key={s.n} className="group relative bg-bg-2/95 p-7 transition hover:bg-bg-2">
            <div className="flex items-center justify-between">
              <span className="num text-sm text-dim">{s.n}</span>
              <StepGlyph i={i} />
            </div>
            <h3 className="mt-10 font-display text-3xl">{s.title}</h3>
            <p className="mt-3 text-sm leading-relaxed text-ink-2">{s.body}</p>
          </div>
        ))}
      </div>

      <div className="panel mt-6 p-7">
        <p className="eyebrow">Why two worlds</p>
        <p className="mt-4 text-lg leading-relaxed text-ink-2">
          Traders are right about an asset and still lose when the world changes under them. A conditional lets you take
          exactly the risk you mean: <span className="text-sun">long ETH if the bill passes</span>, with nothing at stake
          if it doesn&apos;t. Side by side, the two worlds also tell everyone else what the crowd thinks the event will do.
        </p>
      </div>
    </section>
  );
}

function StepGlyph({ i }: { i: number }) {
  const sun = "#FFB547";
  const moon = "#7DE3FF";
  return (
    <svg viewBox="0 0 64 32" className="h-8 w-16" fill="none" aria-hidden>
      <path d="M2 16h22" stroke="#F3EFE7" strokeOpacity={i === 0 ? 0.9 : 0.3} strokeWidth="1.5" />
      <path d="M24 16c10 0 10-10 38-10" stroke={sun} strokeOpacity={i >= 1 ? 0.95 : 0.25} strokeWidth="1.5" />
      <path d="M24 16c10 0 10 10 38 10" stroke={moon} strokeOpacity={i >= 1 && i !== 3 ? 0.95 : 0.2} strokeWidth="1.5" />
      <circle cx="24" cy="16" r="2.4" fill="#FFF8EE" />
      {i >= 2 && <circle cx="62" cy="6" r="2.4" fill={sun} />}
      {i === 2 && <circle cx="62" cy="26" r="2.4" fill={moon} />}
    </svg>
  );
}

const IMD_CARDS = [
  {
    dot: "bg-sun shadow-[0_0_16px_#FFB547]",
    title: "Bets are made in IMD",
    body: "Every market, pot and payout is in IMD.",
  },
  {
    dot: "bg-moon shadow-[0_0_16px_#7DE3FF]",
    title: "Place bets with ETH or USDG",
    body: "Use the ETH or USDG in your wallet to place a bet.",
  },
];

export function ImdSection() {
  return (
    <section id="imd" className="mx-auto mt-32 max-w-7xl scroll-mt-20 px-4 sm:mt-44 sm:px-6">
      <div className="grid gap-10 lg:grid-cols-[1fr_1.4fr]">
        <h2 className="font-display text-5xl leading-[1.02] sm:text-6xl">
          <em className="text-moon-grad">IMD</em>
        </h2>
        <div className="grid gap-4 sm:grid-cols-2">
          {IMD_CARDS.map((c) => (
            <div key={c.title} className="panel p-6">
              <span className={`block h-3 w-3 rounded-full ${c.dot}`} />
              <h3 className="mt-5 text-lg">{c.title}</h3>
              <p className="mt-2 text-sm leading-relaxed text-ink-2">{c.body}</p>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}

export function Footer() {
  return (
    <footer className="mt-36 border-t border-line">
      <div className="mx-auto flex max-w-7xl flex-col gap-8 px-4 py-12 sm:px-6 md:flex-row md:items-end md:justify-between">
        <div>
          <div className="flex items-center gap-2.5">
            <Logo />
            <span className="font-display text-2xl">Conditionals</span>
          </div>
          <p className="mt-3 max-w-sm text-sm text-mute">
            Conditional prediction markets on IMD. Settled by the IdentityMD oracle on Robinhood Chain.
          </p>
        </div>
        <div className="flex flex-wrap gap-x-8 gap-y-3 text-sm text-ink-2">
          <Link href="/wiki" className="hover:text-ink">
            Encyclopedia
          </Link>
          <Link href="/#suggest" className="hover:text-ink">
            Suggest a market
          </Link>
          <Link href="/docs" className="hover:text-ink">
            Docs
          </Link>
          <a href={LINKS.github} target="_blank" rel="noreferrer" className="hover:text-ink">
            GitHub
          </a>
          <a href={LINKS.x} target="_blank" rel="noreferrer" className="hover:text-ink">
            X
          </a>
          <a href={LINKS.imd} target="_blank" rel="noreferrer" className="hover:text-ink">
            IMD
          </a>
        </div>
      </div>
      <p className="pb-10 text-center text-xs text-dim">Not financial advice. Markets can be lost. The oracle can be wrong.</p>
    </footer>
  );
}

export function Toast() {
  const { pending, error, clearError } = useMarkets();
  if (!pending && !error) return null;
  return (
    <div className="fixed inset-x-0 bottom-5 z-[70] flex justify-center px-4">
      <div className={`panel flex max-w-lg items-center gap-3 !rounded-full px-5 py-3 text-sm ${error ? "!border-sun/40" : ""}`}>
        {pending ? (
          <>
            <span className="h-2 w-2 animate-pulse-slow rounded-full bg-moon" />
            <span>{pending}…</span>
          </>
        ) : (
          <>
            <span className="h-2 w-2 rounded-full bg-sun" />
            <span className="line-clamp-2 text-ink-2">{error}</span>
            <button onClick={clearError} className="ml-2 text-mute hover:text-ink">
              ✕
            </button>
          </>
        )}
      </div>
    </div>
  );
}
