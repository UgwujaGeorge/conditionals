import type { MarketView } from "./types";

const DAY = 86_400;

type Seed = Omit<
  MarketView,
  "id" | "closeTime" | "resolveTime" | "voidAfter" | "mine" | "claimable" | "claimed" | "openAsks" | "lastAskAt" | "budget"
> & { closeIn: number; resolveIn: number; asking?: boolean };

const blank = {
  status: "open" as const,
  world: 0 as const,
  winningSide: 0 as const,
  worldRefunded: false,
  answers: [0, 0] as [0, 0],
  netPot: 0,
};

const SEEDS: Seed[] = [
  {
    ...blank,
    tag: "Policy",
    creator: "0x8f3a4d1e0b6c2a9f7e5d3c1b0a9f8e7d6c5b4a39",
    condition: "The Clarity Act (US digital asset market structure bill) is signed into US law by 2026-12-31",
    outcome: "ETH closes above 5000 USD on Coinbase on 2027-01-15",
    rules: "Law: congress.gov bill status shows Became Law. Price: Coinbase ETH-USD daily close (UTC) on 2027-01-15.",
    pools: [
      [612.4, 341.9],
      [188.2, 466.5],
    ],
    closeIn: 18 * DAY,
    resolveIn: 88 * DAY,
  },
  {
    ...blank,
    tag: "Macro",
    creator: "0x1c9e8b7a6d5f4e3c2b1a0f9e8d7c6b5a4f3e2d1c",
    condition: "The Federal Reserve cuts the federal funds target range at its December 2026 FOMC meeting",
    outcome: "BTC closes above 150000 USD on Coinbase on 2027-01-31",
    rules: "Rate decision: the FOMC statement on federalreserve.gov. Price: Coinbase BTC-USD daily close (UTC).",
    pools: [
      [905.0, 702.3],
      [244.8, 731.6],
    ],
    closeIn: 6 * DAY + 7 * 3600,
    resolveIn: 104 * DAY,
  },
  {
    ...blank,
    tag: "IMD",
    creator: "0x4de63474f3715c407dafaa1429fa664559814401",
    condition: "More than 400 IMD launches are live on Robinhood Chain on 2026-12-31 per GET /launches on api.imd.fun",
    outcome: "IMD trades above 60 USD on its most liquid Uniswap pool on 2026-12-31",
    rules: "Count launches with status live and chainId 4663 on api.imd.fun. Price: DexScreener USD price at 23:59 UTC.",
    pools: [
      [221.5, 98.0],
      [76.3, 190.4],
    ],
    closeIn: 2 * DAY + 3 * 3600,
    resolveIn: 73 * DAY,
  },
  {
    ...blank,
    tag: "Equities",
    creator: "0x2b7f6e5d4c3b2a19f8e7d6c5b4a3928170f6e5d4",
    condition: "NVIDIA reports quarterly revenue above 60 billion USD in its next earnings release",
    outcome: "NVDA closes above 220 USD on Nasdaq five trading days after that release",
    rules: "Revenue: NVIDIA's press release on nvidianews.nvidia.com. Price: Nasdaq official close for NVDA.",
    pools: [
      [402.0, 211.7],
      [130.1, 288.9],
    ],
    closeIn: 11 * DAY,
    resolveIn: 45 * DAY,
  },
  {
    ...blank,
    tag: "Crypto",
    creator: "0x9a8b7c6d5e4f3a2b1c0d9e8f7a6b5c4d3e2f1a0b",
    condition: "Ethereum's next scheduled hard fork activates on mainnet by 2027-03-31",
    outcome: "The ETH/BTC ratio closes above 0.045 on Coinbase on 2027-04-07",
    rules: "Fork: the activation epoch announced on blog.ethereum.org is reached. Ratio: Coinbase ETH-BTC daily close.",
    pools: [
      [166.0, 140.2],
      [59.4, 201.8],
    ],
    closeIn: 40 * DAY,
    resolveIn: 170 * DAY,
  },
  {
    ...blank,
    tag: "Macro",
    creator: "0x5e4d3c2b1a0f9e8d7c6b5a4f3e2d1c0b9a8f7e6d",
    condition: "US CPI year-over-year inflation for October 2026 is at or below 2.5 percent",
    outcome: "The S&P 500 closes at a record high at any point in November 2026",
    rules: "CPI: the BLS release on bls.gov (CPI-U, not seasonally adjusted). Record close: S&P Dow Jones Indices.",
    pools: [
      [120.0, 44.6],
      [61.2, 72.8],
    ],
    closeIn: -2 * DAY,
    resolveIn: -6 * 3600,
    asking: true,
  },
  {
    ...blank,
    tag: "Macro",
    creator: "0x7c6b5a4f3e2d1c0b9a8f7e6d5c4b3a2f1e0d9c8b",
    condition: "The Federal Reserve cut the federal funds target range at its September 2025 FOMC meeting",
    outcome: "BTC closed above 100000 USD on Coinbase on 2025-10-01",
    rules: "Rate decision: the FOMC statement on federalreserve.gov. Price: Coinbase BTC-USD daily close (UTC).",
    pools: [
      [540.0, 210.0],
      [90.0, 260.0],
    ],
    closeIn: -60 * DAY,
    resolveIn: -40 * DAY,
    status: "settled",
    world: 0,
    winningSide: 0,
    answers: [1, 1],
    netPot: 750 * 0.97,
  },
];

/** Sample markets for the demo, timed relative to `now` (unix seconds). */
export function demoMarkets(now: number): MarketView[] {
  return SEEDS.map(({ closeIn, resolveIn, asking, ...s }, i) => {
    const resolveTime = Math.floor(now + resolveIn);
    return {
      ...s,
      id: i + 1,
      closeTime: Math.floor(now + closeIn),
      resolveTime,
      voidAfter: resolveTime + 30 * DAY,
      openAsks: asking ? [1, 1] : [0, 0],
      lastAskAt: asking ? [now - 3600, now - 3600] : [0, 0],
      budget: asking || s.status !== "open" ? 0 : 1,
      mine: [
        [0, 0],
        [0, 0],
      ],
      claimable: 0,
      claimed: false,
    };
  });
}
