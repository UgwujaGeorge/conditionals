"use client";

import { useCallback, useMemo, useState } from "react";
import {
  useConnect,
  useConnection,
  useConnectors,
  usePublicClient,
  useReadContract,
  useReadContracts,
  useSwitchChain,
  useWriteContract,
} from "wagmi";
import { decodeEventLog, formatEther, parseEther, type Address, type Hex } from "viem";

import { erc20Abi, factsAbi } from "@/lib/abi";
import { ADDRESSES, chain } from "@/lib/config";
import { PHASES, phaseOf, type FactsSource, type FactView, type Verdict } from "@/lib/facts";
import { useNow } from "./useNow";

const F = ADDRESSES.facts as Address;
const IMD = ADDRESSES.imd;
/** The newest facts the page reads. */
const WINDOW = 300;
const SLIPPAGE = 0.02;

const n = (v: bigint | undefined) => (v === undefined ? 0 : Number(formatEther(v)));
const less = (v: bigint) => (v * BigInt(Math.round((1 - SLIPPAGE) * 10_000))) / 10_000n;

type RawFact = {
  creator: Address;
  rounds: number;
  verdict: number;
  verdictAt: bigint;
  createdAt: bigint;
  b: bigint;
  topic: string;
  claim: string;
  rules: string;
};
type RawRound = {
  seeder: Address;
  phase: number;
  winner: number;
  askedAt: bigint;
  seed: bigint;
  makerBalance: bigint;
  q: readonly [bigint, bigint];
};

export function useLiveFacts(): FactsSource {
  const { address, isConnected, chainId } = useConnection();
  const connectors = useConnectors();
  const { mutate: connectWallet } = useConnect();
  const { mutateAsync: switchChain } = useSwitchChain();
  const { mutateAsync: write } = useWriteContract();
  const client = usePublicClient({ chainId: chain.id });
  const [pending, setPending] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const base = { address: F, abi: factsAbi, chainId: chain.id } as const;
  const countR = useReadContract({ ...base, functionName: "factCount", query: { refetchInterval: 8_000 } });
  const count = Number(countR.data ?? 0n);
  const ids = useMemo(() => {
    const out: number[] = [];
    for (let i = count; i >= 1 && out.length < WINDOW; i--) out.push(i);
    return out;
  }, [count]);

  const factsR = useReadContracts({
    contracts: ids.map((id) => ({ ...base, functionName: "getFact", args: [BigInt(id)] }) as const),
    query: { enabled: ids.length > 0, refetchInterval: 8_000 },
  });
  const rawFacts = ids.map((_, i) => factsR.data?.[i]?.result as RawFact | undefined);
  const roundOf = rawFacts.map((f) => f?.rounds ?? 0);

  const roundsR = useReadContracts({
    contracts: ids.map((id, i) => ({ ...base, functionName: "getRound", args: [BigInt(id), roundOf[i]] }) as const),
    query: { enabled: ids.length > 0 && factsR.isSuccess, refetchInterval: 8_000 },
  });

  // Per fact: the account's shares now, and what it can redeem from this round and the one before.
  const userR = useReadContracts({
    contracts: address
      ? ids.flatMap(
          (id, i) =>
            [
              { ...base, functionName: "sharesOf", args: [BigInt(id), roundOf[i], address] },
              { ...base, functionName: "redeemable", args: [BigInt(id), roundOf[i], address] },
              { ...base, functionName: "redeemable", args: [BigInt(id), Math.max(roundOf[i] - 1, 0), address] },
            ] as const,
        )
      : [],
    query: { enabled: Boolean(address) && factsR.isSuccess, refetchInterval: 8_000 },
  });

  const walletR = useReadContracts({
    contracts: address
      ? ([
          { address: IMD, abi: erc20Abi, functionName: "balanceOf", args: [address], chainId: chain.id },
          { address: IMD, abi: erc20Abi, functionName: "allowance", args: [address, F], chainId: chain.id },
          { ...base, functionName: "owed", args: [address] },
        ] as const)
      : [],
    query: { enabled: Boolean(address), refetchInterval: 8_000 },
  });

  const now = useNow(15_000);
  const facts: FactView[] = useMemo(() => {
    return ids.flatMap((id, i) => {
      const f = rawFacts[i];
      const r = roundsR.data?.[i]?.result as RawRound | undefined;
      if (!f || !r) return [];
      const shares = userR.data?.[i * 3]?.result as readonly [bigint, bigint] | undefined;
      const now0 = n(userR.data?.[i * 3 + 1]?.result as bigint | undefined);
      const prev = n(userR.data?.[i * 3 + 2]?.result as bigint | undefined);
      const redeemable = [
        ...(prev > 0 && f.rounds > 1 ? [{ round: f.rounds - 1, amount: prev }] : []),
        ...(now0 > 0 ? [{ round: f.rounds, amount: now0 }] : []),
      ];
      return [
        {
          id,
          creator: f.creator,
          topic: f.topic,
          claim: f.claim,
          rules: f.rules,
          b: n(f.b),
          round: f.rounds,
          verdict: f.verdict as Verdict,
          verdictAt: Number(f.verdictAt),
          createdAt: Number(f.createdAt),
          phase: phaseOf(PHASES[r.phase] ?? "none", Number(r.askedAt), now),
          askedAt: Number(r.askedAt),
          seeder: r.seeder,
          seed: n(r.seed),
          q: [n(r.q[0]), n(r.q[1])],
          liquidity: n(r.makerBalance),
          mine: shares ? [n(shares[0]), n(shares[1])] : [0, 0],
          redeemable,
        },
      ];
    });
    // rawFacts is derived from factsR.data.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [ids, factsR.data, roundsR.data, userR.data, now]);

  const refresh = useCallback(() => {
    countR.refetch();
    factsR.refetch();
    roundsR.refetch();
    userR.refetch();
    walletR.refetch();
  }, [countR, factsR, roundsR, userR, walletR]);

  const run = useCallback(
    async (label: string, fn: () => Promise<Hex>) => {
      setPending(label);
      setError(null);
      try {
        if (chainId !== chain.id) await switchChain({ chainId: chain.id });
        const hash = await fn();
        setPending("Confirming");
        const receipt = await client?.waitForTransactionReceipt({ hash });
        refresh();
        return receipt;
      } catch (e) {
        const msg = e instanceof Error ? ((e as { shortMessage?: string }).shortMessage ?? e.message.split("\n")[0]) : String(e);
        setError(msg.length > 180 ? `${msg.slice(0, 180)}…` : msg);
        return undefined;
      } finally {
        setPending(null);
      }
    },
    [chainId, client, refresh, switchChain],
  );

  const ensureAllowance = useCallback(
    async (amount: bigint) => {
      const current = (walletR.data?.[1]?.result as bigint | undefined) ?? 0n;
      if (current >= amount) return true;
      const r = await run("Approving IMD", () =>
        write({ address: IMD, abi: erc20Abi, functionName: "approve", args: [F, amount], chainId: chain.id }),
      );
      return Boolean(r);
    },
    [walletR.data, run, write],
  );

  const actions: FactsSource["actions"] = {
    buy: async (id, side, amount) => {
      const wei = parseEther(amount.toFixed(18));
      if (!(await ensureAllowance(wei))) return;
      const [shares] = (await client!.readContract({ ...base, functionName: "quoteBuy", args: [BigInt(id), side, wei] })) as readonly [bigint, bigint, bigint];
      await run("Buying", () => write({ ...base, functionName: "buy", args: [BigInt(id), side, wei, less(shares)] }));
    },
    sell: async (id, side, shares) => {
      const f = facts.find((x) => x.id === id);
      // Selling everything sends the exact holding, so no dust is left behind.
      const held = (userR.data?.[ids.indexOf(id) * 3]?.result as readonly [bigint, bigint] | undefined)?.[side] ?? 0n;
      const wei = f && shares >= f.mine[side] ? held : parseEther(shares.toFixed(18));
      const [proceeds] = (await client!.readContract({ ...base, functionName: "quoteSell", args: [BigInt(id), side, wei] })) as readonly [bigint, bigint];
      await run("Selling", () => write({ ...base, functionName: "sell", args: [BigInt(id), side, wei, less(proceeds)] }));
    },
    challenge: async (id) => {
      const price = (await client!.readContract({ ...base, functionName: "challengePrice", args: [BigInt(id)] })) as bigint;
      if (!(await ensureAllowance(price))) return;
      await run("Asking the swarm", () => write({ ...base, functionName: "challenge", args: [BigInt(id), price] }));
    },
    openRound: async (id) => {
      const f = facts.find((x) => x.id === id);
      if (!f) return;
      const seed = (await client!.readContract({ ...base, functionName: "seedFor", args: [parseEther(f.b.toString())] })) as bigint;
      if (!(await ensureAllowance(seed))) return;
      await run("Opening a round", () => write({ ...base, functionName: "openRound", args: [BigInt(id)] }));
    },
    redeem: async (id, round) => {
      await run("Redeeming", () => write({ ...base, functionName: "redeem", args: [BigInt(id), round] }));
    },
    create: async (input) => {
      const b = parseEther(input.b.toString());
      const seed = (await client!.readContract({ ...base, functionName: "seedFor", args: [b] })) as bigint;
      if (!(await ensureAllowance(seed))) return undefined;
      const receipt = await run("Adding the fact", () =>
        write({ ...base, functionName: "createFact", args: [input.topic, input.claim, input.rules, b] }),
      );
      for (const log of receipt?.logs ?? []) {
        try {
          const ev = decodeEventLog({ abi: factsAbi, data: log.data, topics: log.topics });
          if (ev.eventName === "FactCreated") return Number(ev.args.factId);
        } catch {}
      }
      return undefined;
    },
    withdraw: async () => {
      await run("Withdrawing", () => write({ ...base, functionName: "withdrawOwed" }));
    },
  };

  return {
    live: true,
    ready: countR.isSuccess && (ids.length === 0 || roundsR.isSuccess),
    facts,
    owed: n(walletR.data?.[2]?.result as bigint | undefined),
    balance: n(walletR.data?.[0]?.result as bigint | undefined),
    connected: isConnected,
    connect: () => {
      const c = connectors[0];
      if (c) connectWallet({ connector: c, chainId: chain.id });
      else setError("No browser wallet found. Install MetaMask or Rabby.");
    },
    actions,
    pending,
    error,
    clearError: () => setError(null),
  };
}
