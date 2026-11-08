/** Sample facts for the encyclopedia until its contract is live. Marked as samples on every page that shows them. */

import { qForChance, seedFor, type FactView, type Verdict } from "./facts";

const DAY = 86_400;
const NOW = 1_794_100_000; // 2026-11-07

type Sample = { topic: string; claim: string; rules: string; p: number; verdict?: Verdict; judgedDaysAgo?: number };

const SAMPLES: Sample[] = [
  {
    topic: "Bitcoin",
    claim: "The Bitcoin protocol caps the total supply of bitcoin at 21 million coins",
    rules: "Judge by the Bitcoin Core source code and the Bitcoin whitepaper.",
    p: 0.97,
    verdict: 1,
    judgedDaysAgo: 12,
  },
  {
    topic: "Bitcoin",
    claim: "The April 2024 halving cut the Bitcoin block subsidy to 3.125 BTC",
    rules: "Judge by the Bitcoin block data for block 840000 and the Bitcoin Core source code.",
    p: 0.95,
  },
  {
    topic: "Bitcoin",
    claim: "Satoshi Nakamoto's real identity has been publicly confirmed",
    rules: "True only if Satoshi Nakamoto proved control of early Bitcoin keys or the genesis coins in public.",
    p: 0.04,
    verdict: 2,
    judgedDaysAgo: 30,
  },
  {
    topic: "Bitcoin",
    claim: "Coins mined by Satoshi Nakamoto total about 1 million BTC",
    rules: "Judge by published blockchain analyses of early mining patterns. About means within 10 percent.",
    p: 0.58,
  },
  {
    topic: "Ethereum",
    claim: "Ethereum moved from proof of work to proof of stake in September 2022",
    rules: "Judge by the Ethereum Foundation's records of the Merge and the Ethereum block data.",
    p: 0.98,
    verdict: 1,
    judgedDaysAgo: 4,
  },
  {
    topic: "Ethereum",
    claim: "The Ethereum protocol sets a fixed maximum supply of ETH",
    rules: "Judge by the Ethereum consensus specifications and ethereum.org.",
    p: 0.06,
  },
  {
    topic: "Robinhood Chain",
    claim: "Robinhood Chain is built on Arbitrum technology",
    rules: "Judge by Robinhood's official announcements and the chain's documentation.",
    p: 0.9,
  },
  {
    topic: "IMD",
    claim: "The IMD oracle decides each question with a panel of independent agents",
    rules: "Judge by the IMD documentation at imd.fun/docs.",
    p: 0.88,
  },
  {
    topic: "IMD",
    claim: "IMD trades on Robinhood Chain",
    rules: "Judge by the IMD token contract and DEX pools on Robinhood Chain.",
    p: 0.92,
  },
];

export function demoFacts(): FactView[] {
  return SAMPLES.map((s, i) => {
    const b = 2;
    return {
      id: i + 1,
      creator: "0x0000000000000000000000000000000000000000",
      topic: s.topic,
      claim: s.claim,
      rules: s.rules,
      b,
      round: s.verdict ? 2 : 1,
      verdict: s.verdict ?? 0,
      verdictAt: s.verdict ? NOW - (s.judgedDaysAgo ?? 1) * DAY : 0,
      createdAt: NOW - 40 * DAY,
      phase: "open",
      askedAt: 0,
      seeder: "0x0000000000000000000000000000000000000000",
      seed: seedFor(b),
      q: qForChance(s.p, b),
      liquidity: seedFor(b) + 3,
      mine: [0, 0],
      redeemable: [],
    };
  });
}
