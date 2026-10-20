import { RULES } from "./config";
import type { MarketView, Side, World } from "./types";

export const WORLD_NAMES: Record<World, string> = { 0: "It happens", 1: "It doesn't" };

export function worldPot(m: MarketView, w: World) {
  return m.pools[w][0] + m.pools[w][1];
}

export function totalStaked(m: MarketView) {
  return worldPot(m, 0) + worldPot(m, 1);
}

/** Implied YES probability in a world, from its pools; null when nobody has staked there. */
export function yesChance(m: MarketView, w: World): number | null {
  const pot = worldPot(m, w);
  return pot === 0 ? null : m.pools[w][0] / pot;
}

/** How many points the condition moves the outcome: YES in world 0 minus YES in world 1. */
export function impact(m: MarketView): number | null {
  const a = yesChance(m, 0);
  const b = yesChance(m, 1);
  return a === null || b === null ? null : (a - b) * 100;
}

/** Payout multiple on a winning side, after the 3% fee. */
export function multiple(m: MarketView, w: World, s: Side, extra = 0): number | null {
  const pool = m.pools[w][s] + extra;
  const other = m.pools[w][s === 0 ? 1 : 0];
  if (pool === 0) return null;
  if (other === 0) return 1;
  return ((pool + other) * (1 - RULES.feeBps / 10_000)) / pool;
}

/** What a new stake would pay if its world happens and its side wins. */
export function estimatePayout(m: MarketView, w: World, s: Side, amount: number) {
  if (amount <= 0) return 0;
  const pool = m.pools[w][s] + amount;
  const other = m.pools[w][s === 0 ? 1 : 0];
  if (other === 0) return amount;
  return (amount * (pool + other) * (1 - RULES.feeBps / 10_000)) / pool;
}

export type Stage = "trading" | "closed" | "resolving" | "voidable" | "settled" | "voided";

export function stage(m: MarketView, now: number): Stage {
  if (m.status === "settled") return "settled";
  if (m.status === "voided") return "voided";
  if (now < m.closeTime) return "trading";
  if (now < m.resolveTime) return "closed";
  if (now > m.voidAfter && !settleable(m)) return "voidable";
  return "resolving";
}

export function settleable(m: MarketView) {
  if (m.status !== "open") return false;
  return m.answers[0] === 2 || (m.answers[0] === 1 && m.answers[1] !== 0);
}

/** Whether `requestResolution` would ask something now. */
export function askable(m: MarketView, now: number) {
  if (m.status !== "open" || now < m.resolveTime || now > m.voidAfter) return false;
  const can = (q: 0 | 1) => {
    if (m.answers[q] !== 0) return false;
    if (q === 1 && m.answers[0] === 2) return false;
    return m.openAsks[q] === 0 || now >= m.lastAskAt[q] + RULES.retryHours * 3600;
  };
  return can(0) || can(1);
}

/** Questions the next ask pays for itself: the budget covers 0.5 IMD each. */
export function askCost(m: MarketView, now: number) {
  let n = 0;
  for (const q of [0, 1] as const) {
    if (m.answers[q] !== 0 || (q === 1 && m.answers[0] === 2)) continue;
    if (m.openAsks[q] === 0 || now >= m.lastAskAt[q] + RULES.retryHours * 3600) n++;
  }
  return Math.max(0, n * RULES.oraclePrice - m.budget);
}

export const STAGE_LABEL: Record<Stage, string> = {
  trading: "Live",
  closed: "Closed",
  resolving: "Asking the oracle",
  voidable: "Voidable",
  settled: "Settled",
  voided: "Voided",
};

export function myTotal(m: MarketView) {
  return m.mine[0][0] + m.mine[0][1] + m.mine[1][0] + m.mine[1][1];
}
