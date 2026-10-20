export type Status = "open" | "settled" | "voided";

/** 0: the condition happens, 1: it does not. */
export type World = 0 | 1;
/** 0: YES, 1: NO. */
export type Side = 0 | 1;

/** Answer per question: 0 none, 1 true, 2 false (as the contract stores it). */
export type Answer = 0 | 1 | 2;

export interface MarketView {
  id: number;
  creator: string;
  condition: string;
  outcome: string;
  rules: string;
  /** Unix seconds. */
  closeTime: number;
  resolveTime: number;
  voidAfter: number;
  status: Status;
  world: World;
  winningSide: Side;
  worldRefunded: boolean;
  answers: [Answer, Answer];
  openAsks: [number, number];
  lastAskAt: [number, number];
  budget: number;
  /** pools[world][side], in IMD. */
  pools: [[number, number], [number, number]];
  netPot: number;
  /** The connected trader's stakes, [world][side], and what they can claim now. */
  mine: [[number, number], [number, number]];
  claimable: number;
  claimed: boolean;
  /** Display only: a category tag for demo markets. */
  tag?: string;
}

export interface Totals {
  burned: number;
  builderFees: number;
  oracleSpend: number;
  markets: number;
  staked: number;
}

export interface CreateInput {
  condition: string;
  outcome: string;
  rules: string;
  closeTime: number;
  resolveTime: number;
}

export interface Actions {
  stake: (id: number, world: World, side: Side, amount: number) => Promise<void>;
  create: (input: CreateInput) => Promise<number | undefined>;
  requestResolution: (id: number) => Promise<void>;
  claim: (id: number) => Promise<void>;
  settle: (id: number) => Promise<void>;
  voidMarket: (id: number) => Promise<void>;
  /** Demo only: play the oracle. */
  simulateAnswer?: (id: number, condition: boolean, outcome: boolean) => void;
}

export interface Source {
  live: boolean;
  ready: boolean;
  markets: MarketView[];
  totals: Totals;
  account?: string;
  connected: boolean;
  wrongChain: boolean;
  connect: () => void;
  disconnect: () => void;
  balance: number;
  actions: Actions;
  pending: string | null;
  error: string | null;
  clearError: () => void;
}
