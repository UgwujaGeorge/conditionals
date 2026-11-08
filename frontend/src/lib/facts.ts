/** Fact markets: types, the two-outcome LMSR in floating point, and helpers shared by the page and the server. */

import { FACT_RULES } from "./config";

/** 0: TRUE, 1: FALSE. */
export type FactSide = 0 | 1;
/** As the contract stores it: 0 none, 1 true, 2 false. */
export type Verdict = 0 | 1 | 2;
export type Phase = "none" | "open" | "asking" | "settled" | "closed";
export const PHASES: Phase[] = ["none", "open", "asking", "settled", "closed"];

export interface FactView {
  id: number;
  creator: string;
  topic: string;
  claim: string;
  rules: string;
  b: number;
  /** The current round. */
  round: number;
  verdict: Verdict;
  /** Unix seconds the latest verdict was judged as of. */
  verdictAt: number;
  createdAt: number;
  /** The current round's state. An ask past its timeout reads as open, as the contract treats it. */
  phase: Phase;
  askedAt: number;
  seeder: string;
  seed: number;
  /** Shares of TRUE and FALSE traders hold in the current round. */
  q: [number, number];
  /** IMD backing the current round's maker. */
  liquidity: number;
  /** The connected account's shares in the current round. */
  mine: [number, number];
  /** Winning shares the account can redeem, by round. */
  redeemable: { round: number; amount: number }[];
}

export interface FactInput {
  topic: string;
  claim: string;
  rules: string;
  b: number;
}

export interface FactActions {
  buy: (id: number, side: FactSide, amount: number) => Promise<void>;
  sell: (id: number, side: FactSide, shares: number) => Promise<void>;
  challenge: (id: number) => Promise<void>;
  openRound: (id: number) => Promise<void>;
  redeem: (id: number, round: number) => Promise<void>;
  create: (input: FactInput) => Promise<number | undefined>;
  withdraw: () => Promise<void>;
  /** Sample mode only: play the oracle. */
  simulateVerdict?: (id: number, value: boolean) => void;
}

export interface FactsSource {
  live: boolean;
  ready: boolean;
  facts: FactView[];
  /** IMD that has accrued to the account (seeder fees and residuals). */
  owed: number;
  balance: number;
  connected: boolean;
  connect: () => void;
  actions: FactActions;
  pending: string | null;
  error: string | null;
  clearError: () => void;
}

/** The page a topic lives at: lower case, words joined by dashes. */
export function slugify(topic: string) {
  return topic
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
}

export function phaseOf(raw: Phase, askedAt: number, now = Date.now() / 1000): Phase {
  return raw === "asking" && now >= askedAt + FACT_RULES.askTimeout ? "open" : raw;
}

// LMSR ----------------------------------------------------------------------------------------------------------------

export type Q2 = [number, number];
const FEE = FACT_RULES.feeBps / 10_000;

function normalised(q: Q2, b: number) {
  const max = Math.max(q[0], q[1]);
  return { max, sum: Math.exp((q[0] - max) / b) + Math.exp((q[1] - max) / b) };
}

export function cost(q: Q2, b: number) {
  const { max, sum } = normalised(q, b);
  return max + b * Math.log(sum);
}

/** The chance of TRUE the round's price shows. */
export function pTrue(q: Q2, b: number) {
  return 1 / (1 + Math.exp((q[1] - q[0]) / b));
}

/** What `amount` IMD, fee included, buys of `side`. Mirrors `_buyMath`. */
export function quoteBuy(q: Q2, b: number, side: FactSide, amount: number) {
  const spend = amount / (1 + FEE);
  const { max, sum } = normalised(q, b);
  const e = Math.exp((q[side] - max) / b);
  const shares = b * Math.log((sum * Math.exp(spend / b) - sum + e) / e);
  const after: Q2 = [...q];
  after[side] += shares;
  return { shares, after, fee: amount - spend, limited: Math.abs(after[0] - after[1]) > 20 * b };
}

/** What selling `shares` of `side` pays, after the fee. */
export function quoteSell(q: Q2, b: number, side: FactSide, shares: number) {
  const after: Q2 = [...q];
  after[side] -= shares;
  const gross = cost(q, b) - cost(after, b);
  return { proceeds: gross * (1 - FEE), after };
}

/** The maker position that shows `p` as the chance of TRUE. */
export function qForChance(p: number, b: number): Q2 {
  const gap = b * Math.log(p / (1 - p));
  return gap >= 0 ? [gap, 0] : [0, -gap];
}

export const seedFor = (b: number) => b * Math.LN2;

/** How sure the market is, in words, for the article and the page. */
export function stance(p: number) {
  if (p >= 0.9) return "established";
  if (p >= 0.65) return "likely";
  if (p > 0.35) return "disputed";
  if (p > 0.1) return "doubtful";
  return "rejected";
}
