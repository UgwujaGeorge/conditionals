"use client";

import { useCallback, useMemo, useState } from "react";

import { demoFacts } from "@/lib/factsDemo";
import { quoteBuy, quoteSell, seedFor, type FactsSource, type FactView } from "@/lib/facts";

const wait = (ms: number) => new Promise((r) => setTimeout(r, ms));

/** The encyclopedia on sample facts, with a sample wallet. Nothing is sent anywhere. */
export function useDemoFacts(): FactsSource {
  const [facts, setFacts] = useState<FactView[]>(demoFacts);
  const [balance, setBalance] = useState(100);
  const [pending, setPending] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const update = useCallback((id: number, fn: (f: FactView) => FactView) => {
    setFacts((all) => all.map((f) => (f.id === id ? fn(f) : f)));
  }, []);

  const step = useCallback(async (label: string, fn: () => void) => {
    setPending(label);
    setError(null);
    await wait(500);
    fn();
    setPending(null);
  }, []);

  const actions = useMemo<FactsSource["actions"]>(
    () => ({
      buy: async (id, side, amount) => {
        if (amount > balance) return setError("Not enough IMD in the sample wallet.");
        await step("Buying", () => {
          update(id, (f) => {
            const { shares, after } = quoteBuy(f.q, f.b, side, amount);
            const mine: [number, number] = [...f.mine];
            mine[side] += shares;
            return { ...f, q: after, mine, liquidity: f.liquidity + amount };
          });
          setBalance((b) => b - amount);
        });
      },
      sell: async (id, side, shares) => {
        await step("Selling", () => {
          let got = 0;
          update(id, (f) => {
            const { proceeds, after } = quoteSell(f.q, f.b, side, shares);
            got = proceeds;
            const mine: [number, number] = [...f.mine];
            mine[side] -= shares;
            return { ...f, q: after, mine, liquidity: f.liquidity - proceeds };
          });
          setBalance((b) => b + got);
        });
      },
      challenge: async (id) => {
        await step("Asking the swarm", () => {
          update(id, (f) => ({ ...f, phase: "asking", askedAt: Date.now() / 1000 }));
          setBalance((b) => b - 0.5);
        });
      },
      simulateVerdict: (id, value) => {
        update(id, (f) => {
          const won = f.mine[value ? 0 : 1];
          return {
            ...f,
            phase: "settled",
            verdict: value ? 1 : 2,
            verdictAt: f.askedAt || Date.now() / 1000,
            redeemable: won > 0 ? [...f.redeemable, { round: f.round, amount: won }] : f.redeemable,
            mine: [0, 0],
          };
        });
      },
      openRound: async (id) => {
        await step("Opening a round", () => {
          update(id, (f) => ({ ...f, phase: "open", round: f.round + 1, q: [0, 0], mine: [0, 0], askedAt: 0, liquidity: seedFor(f.b) }));
          setBalance((b) => b - seedFor(2));
        });
      },
      redeem: async (id, round) => {
        await step("Redeeming", () => {
          let got = 0;
          update(id, (f) => {
            got = f.redeemable.find((r) => r.round === round)?.amount ?? 0;
            return { ...f, redeemable: f.redeemable.filter((r) => r.round !== round) };
          });
          setBalance((b) => b + got);
        });
      },
      create: async (input) => {
        let id = 0;
        await step("Adding the fact", () => {
          setFacts((all) => {
            id = all.length + 1;
            return [
              ...all,
              {
                id,
                creator: "you",
                topic: input.topic,
                claim: input.claim,
                rules: input.rules,
                b: input.b,
                round: 1,
                verdict: 0,
                verdictAt: 0,
                createdAt: Date.now() / 1000,
                phase: "open",
                askedAt: 0,
                seeder: "you",
                seed: seedFor(input.b),
                q: [0, 0],
                liquidity: seedFor(input.b),
                mine: [0, 0],
                redeemable: [],
              },
            ];
          });
          setBalance((b) => b - seedFor(input.b));
        });
        return id;
      },
      withdraw: async () => {},
    }),
    [balance, step, update],
  );

  return {
    live: false,
    ready: true,
    facts,
    owed: 0,
    balance,
    connected: true,
    connect: () => {},
    actions,
    pending,
    error,
    clearError: () => setError(null),
  };
}
