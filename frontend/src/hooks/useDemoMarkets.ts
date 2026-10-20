"use client";

import { useCallback, useEffect, useMemo, useState } from "react";

import { RULES } from "@/lib/config";
import { demoMarkets } from "@/lib/demo";
import type { Actions, MarketView, Side, Source, World } from "@/lib/types";

const DEMO_ACCOUNT = "0xdem0000000000000000000000000000000000000";
const wait = (ms: number) => new Promise((r) => setTimeout(r, ms));

/** Same rules as the contract, in memory: stake, ask, answer (you play the oracle), settle, claim. */
function payout(m: MarketView): number {
  const s = m.mine;
  if (m.status === "voided") return s[0][0] + s[0][1] + s[1][0] + s[1][1];
  if (m.status !== "settled") return 0;
  const w = m.world;
  const o = (1 - w) as World;
  let amount = s[o][0] + s[o][1];
  if (m.worldRefunded) amount += s[w][0] + s[w][1];
  else if (s[w][m.winningSide] > 0) amount += (s[w][m.winningSide] * m.netPot) / m.pools[w][m.winningSide];
  return amount;
}

function settle(m: MarketView): { market: MarketView; burned: number; fee: number } {
  const world: World = m.answers[0] === 1 ? 0 : 1;
  const side: Side = m.answers[1] === 1 ? 0 : 1;
  const [yes, no] = m.pools[world];
  const next: MarketView = { ...m, status: "settled", world, winningSide: side, budget: 0 };
  if (yes === 0 || no === 0) return { market: { ...next, worldRefunded: true }, burned: 0, fee: 0 };
  const pot = yes + no;
  const losing = side === 0 ? no : yes;
  let burned = (pot * RULES.burnBps) / 10_000;
  let fee = (pot * RULES.builderBps) / 10_000;
  if (burned + fee > losing) {
    // As the contract: the fee is capped at the losing pool, split 2:1 between the burn and the builder.
    burned = (losing * RULES.burnBps) / RULES.feeBps;
    fee = losing - burned;
  }
  return { market: { ...next, netPot: pot - burned - fee }, burned, fee };
}

export function useDemoMarkets(): Source {
  const [markets, setMarkets] = useState<MarketView[]>([]);
  const [balance, setBalance] = useState(250);
  const [pending, setPending] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [burned, setBurned] = useState(41.37);
  const [builderFees, setBuilderFees] = useState(20.69);
  const [oracleSpend, setOracleSpend] = useState(9);

  // Sample markets are timed from the browser's clock, never during prerender.
  useEffect(() => {
    const load = () => setMarkets(demoMarkets(Math.floor(Date.now() / 1000)));
    load();
  }, []);

  const update = useCallback((id: number, fn: (m: MarketView) => MarketView) => {
    setMarkets((ms) => ms.map((m) => (m.id === id ? withClaimable(fn(m)) : m)));
  }, []);

  const busy = useCallback(async (label: string, fn: () => void) => {
    setPending(label);
    await wait(650);
    fn();
    setPending(null);
  }, []);

  const actions: Actions = useMemo(
    () => ({
      stake: async (id, world, side, amount) => {
        if (amount < RULES.minStake) return setError(`The smallest stake is ${RULES.minStake} IMD.`);
        if (amount > balance) return setError("Not enough demo IMD.");
        await busy("Staking", () => {
          setBalance((b) => b - amount);
          update(id, (m) => {
            const pools = m.pools.map((p) => [...p]) as MarketView["pools"];
            const mine = m.mine.map((p) => [...p]) as MarketView["mine"];
            pools[world][side] += amount;
            mine[world][side] += amount;
            return { ...m, pools, mine };
          });
        });
      },
      create: async (input) => {
        if (balance < RULES.creationDeposit) {
          setError("Not enough demo IMD for the 1 IMD oracle deposit.");
          return undefined;
        }
        const id = markets.reduce((max, m) => Math.max(max, m.id), 0) + 1;
        await busy("Creating market", () => {
          setBalance((b) => b - RULES.creationDeposit);
          setMarkets((ms) => {
            const m: MarketView = {
              id,
              creator: DEMO_ACCOUNT,
              condition: input.condition,
              outcome: input.outcome,
              rules: input.rules,
              closeTime: input.closeTime,
              resolveTime: input.resolveTime,
              voidAfter: input.resolveTime + RULES.resolutionDays * 86_400,
              status: "open",
              world: 0,
              winningSide: 0,
              worldRefunded: false,
              answers: [0, 0],
              openAsks: [0, 0],
              lastAskAt: [0, 0],
              budget: RULES.creationDeposit,
              pools: [
                [0, 0],
                [0, 0],
              ],
              netPot: 0,
              mine: [
                [0, 0],
                [0, 0],
              ],
              claimable: 0,
              claimed: false,
              tag: "New",
            };
            return [m, ...ms];
          });
        });
        return id;
      },
      requestResolution: async (id) => {
        await busy("Paying the oracle", () => {
          const now = Math.floor(Date.now() / 1000);
          setOracleSpend((s) => s + 1);
          update(id, (m) => ({ ...m, budget: 0, openAsks: [1, 1], lastAskAt: [now, now] }));
        });
      },
      claim: async (id) => {
        const amount = markets.find((m) => m.id === id)?.claimable ?? 0;
        await busy("Claiming", () => {
          setBalance((b) => b + amount);
          update(id, (m) => ({ ...m, claimed: true }));
        });
      },
      settle: async () => {},
      voidMarket: async (id) => {
        await busy("Voiding", () => update(id, (m) => ({ ...m, status: "voided" })));
      },
      simulateAnswer: (id, condition, outcome) => {
        const m = markets.find((x) => x.id === id);
        if (!m || m.status !== "open") return;
        const answered: MarketView = {
          ...m,
          answers: [condition ? 1 : 2, condition ? (outcome ? 1 : 2) : 0],
          openAsks: [0, 0],
        };
        const { market, burned: b, fee } = settle(answered);
        setBurned((x) => x + b);
        setBuilderFees((x) => x + fee);
        update(id, () => market);
      },
    }),
    [balance, busy, update, markets],
  );

  const totals = useMemo(() => {
    const staked = markets.reduce((s, m) => s + m.pools[0][0] + m.pools[0][1] + m.pools[1][0] + m.pools[1][1], 0);
    return { burned, builderFees, oracleSpend, markets: markets.length, staked };
  }, [markets, burned, builderFees, oracleSpend]);

  return {
    live: false,
    ready: markets.length > 0,
    markets,
    totals,
    account: DEMO_ACCOUNT,
    connected: true,
    wrongChain: false,
    connect: () => {},
    disconnect: () => {},
    balance,
    actions,
    pending,
    error,
    clearError: () => setError(null),
  };
}

function withClaimable(m: MarketView): MarketView {
  return m.claimed ? { ...m, claimable: 0 } : { ...m, claimable: payout(m) };
}
