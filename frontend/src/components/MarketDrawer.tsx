"use client";

import { useEffect, useState } from "react";
import { AnimatePresence, motion } from "motion/react";

import { useMarkets } from "./Providers";
import { StageChip } from "./MarketCard";
import { FlameIcon, OracleIcon } from "./Glyphs";
import { ADDRESSES, LINKS, RULES } from "@/lib/config";
import { fmtCountdown, fmtDate, fmtImd, fmtPct, fmtPts, short } from "@/lib/format";
import {
  askable,
  askCost,
  estimatePayout,
  impact,
  multiple,
  myTotal,
  settleable,
  stage,
  worldPot,
  yesChance,
} from "@/lib/market";
import type { MarketView, Side, World } from "@/lib/types";

const WORLD = {
  0: {
    name: "World A",
    label: "if it happens",
    text: "text-sun",
    grad: "text-sun-grad",
    ring: "border-sun/60 bg-sun/[0.07] shadow-[0_0_0_1px_rgba(255,181,71,0.25),0_20px_60px_-25px_rgba(255,181,71,0.5)]",
    btn: "bg-gradient-to-r from-sun to-sun-2 text-bg",
  },
  1: {
    name: "World B",
    label: "if it doesn't",
    text: "text-moon",
    grad: "text-moon-grad",
    ring: "border-moon/60 bg-moon/[0.07] shadow-[0_0_0_1px_rgba(125,227,255,0.25),0_20px_60px_-25px_rgba(125,227,255,0.5)]",
    btn: "bg-gradient-to-r from-moon to-moon-2 text-bg",
  },
} as const;

export function MarketDrawer({ id, now, onClose }: { id: number | null; now: number; onClose: () => void }) {
  const { markets } = useMarkets();
  const m = markets.find((x) => x.id === id);

  useEffect(() => {
    if (!m) return;
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && onClose();
    window.addEventListener("keydown", onKey);
    document.body.style.overflow = "hidden";
    return () => {
      window.removeEventListener("keydown", onKey);
      document.body.style.overflow = "";
    };
  }, [m, onClose]);

  return (
    <AnimatePresence>
      {m && (
        <motion.div className="fixed inset-0 z-50 flex justify-end" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}>
          <button aria-label="Close" className="absolute inset-0 bg-black/70 backdrop-blur-sm" onClick={onClose} />
          <motion.aside
            role="dialog"
            aria-modal
            className="relative flex h-full w-full max-w-[46rem] flex-col overflow-y-auto border-l border-line bg-bg-2 scrollbar-none"
            initial={{ x: "100%" }}
            animate={{ x: 0 }}
            exit={{ x: "100%" }}
            transition={{ type: "spring", stiffness: 260, damping: 32 }}
          >
            <Body m={m} now={now} onClose={onClose} />
          </motion.aside>
        </motion.div>
      )}
    </AnimatePresence>
  );
}

function Body({ m, now, onClose }: { m: MarketView; now: number; onClose: () => void }) {
  const [world, setWorld] = useState<World>(0);
  const [side, setSide] = useState<Side>(0);
  const [amount, setAmount] = useState("10");
  const s = stage(m, now);

  return (
    <>
      <div className="sticky top-0 z-10 flex items-center justify-between gap-3 border-b border-line bg-bg-2/85 px-5 py-4 backdrop-blur-xl sm:px-8">
        <div className="flex items-center gap-2">
          <StageChip m={m} now={now} />
          <span className="eyebrow !text-[0.62rem]">#{m.id}</span>
        </div>
        <button onClick={onClose} className="btn btn-ghost !h-9 !w-9 !p-0" aria-label="Close">
          <svg viewBox="0 0 24 24" className="h-4 w-4" fill="none">
            <path d="M6 6l12 12M18 6 6 18" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" />
          </svg>
        </button>
      </div>

      <div className="px-5 pb-16 pt-8 sm:px-8">
        <p className="eyebrow !text-sun/80">If</p>
        <h2 className="mt-2 font-display text-[2.1rem] leading-[1.08] sm:text-[2.6rem]">{m.condition}</h2>
        <p className="eyebrow mt-6">Will</p>
        <p className="mt-2 text-xl leading-snug text-ink-2">{m.outcome}?</p>

        <Worlds m={m} world={world} setWorld={setWorld} />

        {s === "trading" ? (
          <StakeBox m={m} world={world} side={side} setSide={setSide} amount={amount} setAmount={setAmount} now={now} />
        ) : null}

        <Position m={m} />
        <Resolution m={m} now={now} />
        <Details m={m} />
      </div>
    </>
  );
}

function Worlds({ m, world, setWorld }: { m: MarketView; world: World; setWorld: (w: World) => void }) {
  const delta = impact(m);
  const settled = m.status === "settled";
  return (
    <div className="mt-8">
      <div className="grid grid-cols-2 gap-3">
        {([0, 1] as const).map((w) => {
          const st = WORLD[w];
          const happened = settled && m.world === w;
          const gone = settled && m.world !== w;
          return (
            <button
              key={w}
              onClick={() => setWorld(w)}
              className={`relative overflow-hidden rounded-2xl border p-4 text-left transition duration-300 sm:p-5 ${
                world === w ? st.ring : "border-line bg-white/[0.02] hover:border-line-2"
              } ${gone ? "opacity-40" : ""}`}
            >
              <p className={`eyebrow !text-[0.62rem] ${st.text}`}>
                {st.name} · {st.label}
              </p>
              <p className={`mt-3 font-display text-6xl leading-none ${st.grad}`}>{fmtPct(yesChance(m, w))}</p>
              <p className="mt-1 text-xs text-mute">chance of YES</p>
              <div className="mt-4 flex items-center justify-between text-xs">
                <span className="num text-ink-2">{fmtImd(worldPot(m, w))} IMD</span>
                {happened && <span className={`chip !py-0.5 ${st.text}`}>Happened</span>}
                {gone && <span className="chip !py-0.5">Refunded</span>}
              </div>
              <PoolBar m={m} w={w} />
            </button>
          );
        })}
      </div>
      <p className="mt-3 text-center text-sm text-mute">
        The condition moves the outcome by <span className="num text-ink">{fmtPts(delta)}</span> points
      </p>
    </div>
  );
}

function PoolBar({ m, w }: { m: MarketView; w: World }) {
  const pot = worldPot(m, w);
  const yes = pot === 0 ? 50 : (m.pools[w][0] / pot) * 100;
  return (
    <div className="mt-3 flex h-1.5 overflow-hidden rounded-full bg-white/5">
      <div className={w === 0 ? "bg-sun" : "bg-moon"} style={{ width: `${yes}%` }} />
      <div className="bg-white/15" style={{ width: `${100 - yes}%` }} />
    </div>
  );
}

function StakeBox({
  m,
  world,
  side,
  setSide,
  amount,
  setAmount,
  now,
}: {
  m: MarketView;
  world: World;
  side: Side;
  setSide: (s: Side) => void;
  amount: string;
  setAmount: (a: string) => void;
  now: number;
}) {
  const src = useMarkets();
  const st = WORLD[world];
  const value = Number(amount) || 0;
  const payout = estimatePayout(m, world, side, value);
  const mult = multiple(m, world, side, value);
  const other = (1 - world) as World;
  const tooSmall = value > 0 && value < RULES.minStake;
  const tooBig = src.connected && value > src.balance;

  return (
    <div className="panel mt-8 p-5 sm:p-6">
      <div className="flex items-center justify-between">
        <p className="eyebrow">
          Stake in <span className={st.text}>{st.name}</span>
        </p>
        <p className="text-xs text-mute">closes in {fmtCountdown(m.closeTime - now)}</p>
      </div>

      <div className="mt-4 grid grid-cols-2 gap-2 rounded-2xl border border-line bg-black/30 p-1.5">
        {([0, 1] as const).map((sd) => (
          <button
            key={sd}
            onClick={() => setSide(sd)}
            className={`rounded-xl py-3 text-sm font-medium transition ${side === sd ? (sd === 0 ? st.btn : "bg-ink text-bg") : "text-ink-2 hover:text-ink"}`}
          >
            {sd === 0 ? "YES" : "NO"}
            <span className="num ml-2 opacity-70">
              {fmtPct(sd === 0 ? yesChance(m, world) : yesChance(m, world) === null ? null : 1 - (yesChance(m, world) ?? 0))}
            </span>
          </button>
        ))}
      </div>

      <div className="mt-4 flex items-center gap-2">
        <div className="relative flex-1">
          <input
            inputMode="decimal"
            value={amount}
            onChange={(e) => setAmount(e.target.value.replace(/[^0-9.]/g, ""))}
            className="field num !py-3.5 !pr-16 text-xl"
            aria-label="Amount in IMD"
          />
          <span className="pointer-events-none absolute right-4 top-1/2 -translate-y-1/2 text-sm text-mute">IMD</span>
        </div>
      </div>
      <div className="mt-2 flex gap-1.5">
        {["1", "5", "25", "100"].map((v) => (
          <button key={v} onClick={() => setAmount(v)} className="chip hover:border-line-2 hover:text-ink">
            {v}
          </button>
        ))}
        {src.connected && (
          <button
            onClick={() => setAmount(String(Math.floor(src.balance * 1000) / 1000))}
            className="chip hover:border-line-2 hover:text-ink"
          >
            Max
          </button>
        )}
      </div>

      <div className="mt-5 space-y-2.5 rounded-2xl border border-line bg-black/25 p-4 text-sm">
        <Row
          k={
            <>
              <span className={st.text}>{cap(st.label)}</span> and {side === 0 ? "YES" : "NO"} wins
            </>
          }
          v={
            <span className="num text-ink">
              {fmtImd(payout)} IMD <span className="text-mute">{mult ? `×${mult.toFixed(2)}` : ""}</span>
            </span>
          }
        />
        <Row
          k={<span className={WORLD[other].text}>{cap(WORLD[other].label)}</span>}
          v={<span className="num text-ink-2">refunded · {fmtImd(value)} IMD</span>}
        />
        <Row k={<>If {side === 0 ? "NO" : "YES"} wins</>} v={<span className="num text-mute">0</span>} />
      </div>

      <button
        disabled={!value || tooSmall || tooBig || Boolean(src.pending)}
        onClick={() => (src.connected ? src.actions.stake(m.id, world, side, value) : src.connect())}
        className={`btn mt-5 w-full !py-4 text-base ${st.btn}`}
      >
        {!src.connected
          ? "Connect wallet"
          : tooSmall
            ? `Minimum ${RULES.minStake} IMD`
            : tooBig
              ? "Not enough IMD"
              : src.pending ?? `Stake ${fmtImd(value)} IMD on ${side === 0 ? "YES" : "NO"} in ${st.name}`}
      </button>
      <p className="mt-3 text-center text-xs text-mute">
        3% of the winning world&apos;s pot is taken at settlement: 2% burned, 1% to the builder. The fee never
        exceeds the losing side&apos;s stakes, so a winner never nets less than staked.
      </p>
    </div>
  );
}

const cap = (s: string) => s.charAt(0).toUpperCase() + s.slice(1);

function Row({ k, v }: { k: React.ReactNode; v: React.ReactNode }) {
  return (
    <div className="flex items-center justify-between gap-4">
      <span className="text-ink-2">{k}</span>
      {v}
    </div>
  );
}

function Position({ m }: { m: MarketView }) {
  const src = useMarkets();
  const total = myTotal(m);
  if (!src.connected || (total === 0 && m.claimable === 0 && !m.claimed)) return null;
  return (
    <div className="panel mt-6 p-5 sm:p-6">
      <div className="flex items-center justify-between">
        <p className="eyebrow">Your position</p>
        {m.claimed && <span className="chip">Claimed</span>}
      </div>
      <div className="mt-4 grid grid-cols-2 gap-3 text-sm">
        {([0, 1] as const).map((w) => (
          <div key={w} className="rounded-xl border border-line bg-black/20 p-3">
            <p className={`eyebrow !text-[0.6rem] ${WORLD[w].text}`}>{WORLD[w].name}</p>
            <p className="mt-2 flex justify-between">
              <span className="text-mute">YES</span>
              <span className="num">{fmtImd(m.mine[w][0])}</span>
            </p>
            <p className="flex justify-between">
              <span className="text-mute">NO</span>
              <span className="num">{fmtImd(m.mine[w][1])}</span>
            </p>
          </div>
        ))}
      </div>
      {m.claimable > 0 && (
        <button onClick={() => src.actions.claim(m.id)} disabled={Boolean(src.pending)} className="btn btn-primary mt-4 w-full !py-3.5">
          {src.pending ?? `Claim ${fmtImd(m.claimable)} IMD`}
        </button>
      )}
      {m.status === "open" && settleable(m) && total > 0 && (
        <button onClick={() => src.actions.claim(m.id)} disabled={Boolean(src.pending)} className="btn btn-primary mt-4 w-full !py-3.5">
          {src.pending ?? "Settle and claim"}
        </button>
      )}
    </div>
  );
}

function Resolution({ m, now }: { m: MarketView; now: number }) {
  const src = useMarkets();
  const s = stage(m, now);
  const asked = m.openAsks[0] + m.openAsks[1] > 0 || m.answers[0] !== 0 || m.status !== "open";
  const answer = (a: number) => (a === 1 ? "YES" : a === 2 ? "NO" : null);
  const steps = [
    { label: "Trading", sub: `until ${fmtDate(m.closeTime)}`, done: now >= m.closeTime, active: s === "trading" },
    { label: "Closed", sub: `judged as of ${fmtDate(m.resolveTime)}`, done: now >= m.resolveTime, active: s === "closed" },
    {
      label: "Oracle asked",
      sub: `2 questions · panel of ${RULES.panelSize}, quorum ${RULES.quorum}`,
      done: asked,
      active: s === "resolving" && !asked,
    },
    {
      label: "Answered",
      sub:
        m.answers[0] === 0 && m.answers[1] === 0
          ? "waiting for the panel"
          : `condition ${answer(m.answers[0])} · outcome ${answer(m.answers[1]) ?? "pending"}`,
      done: settleable(m) || m.status !== "open",
      active: s === "resolving" && asked,
    },
    {
      label: m.status === "voided" ? "Voided" : "Settled",
      sub:
        m.status === "settled"
          ? m.worldRefunded
            ? "one-sided world, refunded"
            : `${m.world === 0 ? "World A" : "World B"} · ${m.winningSide === 0 ? "YES" : "NO"} won`
          : m.status === "voided"
            ? "every stake refunded"
            : `void after ${fmtDate(m.voidAfter)} if unanswered`,
      done: m.status !== "open",
      active: false,
    },
  ];

  const cost = askCost(m, now);
  return (
    <div className="mt-6">
      <p className="eyebrow">Resolution</p>
      <ol className="relative mt-5 space-y-5 pl-7">
        <span className="absolute bottom-2 left-[7px] top-2 w-px bg-line-2" />
        {steps.map((st) => (
          <li key={st.label} className="relative">
            <span
              className={`absolute -left-7 top-1 h-[15px] w-[15px] rounded-full border ${
                st.done ? "border-sun bg-sun" : st.active ? "animate-pulse-slow border-moon bg-moon/40" : "border-line-2 bg-bg-2"
              }`}
            />
            <p className={st.done || st.active ? "text-ink" : "text-mute"}>{st.label}</p>
            <p className="text-xs text-mute">{st.sub}</p>
          </li>
        ))}
      </ol>

      <div className="mt-6 flex flex-wrap gap-2">
        {askable(m, now) && (
          <button onClick={() => src.actions.requestResolution(m.id)} disabled={Boolean(src.pending)} className="btn btn-primary">
            <OracleIcon className="h-4 w-4" />
            {src.pending ?? (cost > 0 ? `Ask the oracle (${fmtImd(cost)} IMD)` : "Ask the oracle")}
          </button>
        )}
        {m.status === "open" && settleable(m) && (
          <button onClick={() => src.actions.settle(m.id)} disabled={Boolean(src.pending)} className="btn btn-ghost">
            Settle
          </button>
        )}
        {s === "voidable" && (
          <button onClick={() => src.actions.voidMarket(m.id)} disabled={Boolean(src.pending)} className="btn btn-ghost">
            Void and refund everyone
          </button>
        )}
      </div>
      {askable(m, now) && (
        <p className="mt-3 text-xs text-mute">
          Anyone can ask. The first ask of each question is paid from the creator&apos;s deposit; a retry costs{" "}
          {RULES.oraclePrice} IMD.
        </p>
      )}

      {!src.live && m.status === "open" && now >= m.resolveTime && (
        <div className="mt-6 rounded-2xl border border-dashed border-line-2 p-4">
          <p className="eyebrow !text-[0.62rem]">Demo · play the oracle</p>
          <div className="mt-3 flex flex-wrap gap-2">
            <button onClick={() => src.actions.simulateAnswer?.(m.id, true, true)} className="chip hover:text-ink">
              Happened · YES
            </button>
            <button onClick={() => src.actions.simulateAnswer?.(m.id, true, false)} className="chip hover:text-ink">
              Happened · NO
            </button>
            <button onClick={() => src.actions.simulateAnswer?.(m.id, false, false)} className="chip hover:text-ink">
              Didn&apos;t happen
            </button>
          </div>
        </div>
      )}
    </div>
  );
}

function Details({ m }: { m: MarketView }) {
  const settled = m.status === "settled" && !m.worldRefunded;
  const pot = settled ? worldPot(m, m.world) : 0;
  return (
    <div className="mt-8 space-y-4">
      <div className="rounded-2xl border border-line p-4 sm:p-5">
        <p className="eyebrow">How the oracle judges it</p>
        <p className="mt-3 text-sm leading-relaxed text-ink-2">{m.rules}</p>
        <p className="mt-3 text-xs leading-relaxed text-mute">
          Both statements are judged as of {fmtDate(m.resolveTime)}. A panel of {RULES.panelSize} IMD agents answers each
          one; {RULES.quorum} must agree. The contract accepts only an answer signed by the oracle for this exact
          question.
        </p>
      </div>
      <div className="grid gap-3 text-sm sm:grid-cols-2">
        <Info k="Creator" v={short(m.creator)} />
        <Info k="Oracle deposit left" v={`${fmtImd(m.budget)} IMD`} />
        <Info k="Oracle signer" v={short(ADDRESSES.oracleSigner)} />
        <Info k="Intake" v={short(ADDRESSES.intake)} />
      </div>
      {settled && (
        <div className="flex items-center gap-3 rounded-2xl border border-burn/30 bg-burn/[0.06] p-4 text-sm">
          <FlameIcon className="h-5 w-5 text-burn" />
          <span className="text-ink-2">
            Burned <span className="num text-ink">{fmtImd((pot * RULES.burnBps) / 10_000)} IMD</span> from this market.
          </span>
        </div>
      )}
      {ADDRESSES.conditionals && (
        <a href={`${LINKS.explorer}/address/${ADDRESSES.conditionals}`} target="_blank" rel="noreferrer" className="block text-xs text-mute hover:text-ink">
          View the contract on Blockscout ↗
        </a>
      )}
    </div>
  );
}

function Info({ k, v }: { k: string; v: string }) {
  return (
    <div className="flex items-center justify-between rounded-xl border border-line px-4 py-3">
      <span className="text-mute">{k}</span>
      <span className="num text-ink-2">{v}</span>
    </div>
  );
}
