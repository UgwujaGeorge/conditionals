"use client";

import { useCallback, useMemo, useState } from "react";
import {
  useConnect,
  useConnection,
  useConnectors,
  useDisconnect,
  usePublicClient,
  useReadContract,
  useReadContracts,
  useSwitchChain,
  useWriteContract,
} from "wagmi";
import { decodeEventLog, formatEther, parseEther, type Address, type Hex } from "viem";

import { conditionalsAbi, erc20Abi } from "@/lib/abi";
import { ADDRESSES, chain, RULES } from "@/lib/config";
import { askCost } from "@/lib/market";
import type { Actions, Answer, MarketView, Side, Source, Status } from "@/lib/types";

const C = ADDRESSES.conditionals as Address;
const IMD = ADDRESSES.imd;
/** The newest markets the page reads. */
const WINDOW = 60;

const n = (v: bigint | undefined) => (v === undefined ? 0 : Number(formatEther(v)));
const STATUS: Status[] = ["open", "settled", "voided"];

type RawMarket = {
  creator: Address;
  closeTime: bigint;
  resolveTime: bigint;
  voidAfter: bigint;
  status: number;
  world: number;
  winningSide: number;
  worldRefunded: boolean;
  answers: readonly [number, number];
  openAsks: readonly [number, number];
  lastAskAt: readonly [bigint, bigint];
  budget: bigint;
  pools: readonly [readonly [bigint, bigint], readonly [bigint, bigint]];
  netPot: bigint;
  condition: string;
  outcome: string;
  rules: string;
};

export function useLiveMarkets(): Source {
  const { address, isConnected, chainId } = useConnection();
  const connectors = useConnectors();
  const { mutate: connectWallet } = useConnect();
  const { mutate: disconnectWallet } = useDisconnect();
  const { mutateAsync: switchChain } = useSwitchChain();
  const { mutateAsync: write } = useWriteContract();
  const client = usePublicClient({ chainId: chain.id });

  const [pending, setPending] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const base = { address: C, abi: conditionalsAbi, chainId: chain.id } as const;
  const core = useReadContracts({
    contracts: [
      { ...base, functionName: "marketCount" },
      { ...base, functionName: "totalBurned" },
      { ...base, functionName: "totalBuilderFees" },
      { ...base, functionName: "totalOracleSpend" },
    ],
    query: { refetchInterval: 6_000 },
  });
  const count = Number(core.data?.[0]?.result ?? 0n);
  const ids = useMemo(() => {
    const out: number[] = [];
    for (let i = count; i >= 1 && out.length < WINDOW; i--) out.push(i);
    return out;
  }, [count]);

  const marketsR = useReadContracts({
    contracts: ids.map((id) => ({ ...base, functionName: "getMarket", args: [BigInt(id)] }) as const),
    query: { enabled: ids.length > 0, refetchInterval: 6_000 },
  });

  const userR = useReadContracts({
    contracts: address
      ? ids.flatMap(
          (id) =>
            [
              { ...base, functionName: "stakesOf", args: [BigInt(id), address] },
              { ...base, functionName: "claimable", args: [BigInt(id), address] },
              { ...base, functionName: "claimed", args: [BigInt(id), address] },
            ] as const,
        )
      : [],
    query: { enabled: Boolean(address) && ids.length > 0, refetchInterval: 6_000 },
  });

  const balanceR = useReadContract({
    address: IMD,
    abi: erc20Abi,
    functionName: "balanceOf",
    args: address ? [address] : undefined,
    chainId: chain.id,
    query: { enabled: Boolean(address), refetchInterval: 6_000 },
  });
  const allowanceR = useReadContract({
    address: IMD,
    abi: erc20Abi,
    functionName: "allowance",
    args: address ? [address, C] : undefined,
    chainId: chain.id,
    query: { enabled: Boolean(address), refetchInterval: 6_000 },
  });

  const markets: MarketView[] = useMemo(() => {
    return ids.flatMap((id, i) => {
      const raw = marketsR.data?.[i]?.result as RawMarket | undefined;
      if (!raw) return [];
      const stakes = userR.data?.[i * 3]?.result as readonly [readonly [bigint, bigint], readonly [bigint, bigint]] | undefined;
      return [
        {
          id,
          creator: raw.creator,
          condition: raw.condition,
          outcome: raw.outcome,
          rules: raw.rules,
          closeTime: Number(raw.closeTime),
          resolveTime: Number(raw.resolveTime),
          voidAfter: Number(raw.voidAfter),
          status: STATUS[raw.status] ?? "open",
          world: (raw.world === 1 ? 1 : 0) as 0 | 1,
          winningSide: (raw.winningSide === 1 ? 1 : 0) as Side,
          worldRefunded: raw.worldRefunded,
          answers: [raw.answers[0] as Answer, raw.answers[1] as Answer],
          openAsks: [Number(raw.openAsks[0]), Number(raw.openAsks[1])],
          lastAskAt: [Number(raw.lastAskAt[0]), Number(raw.lastAskAt[1])],
          budget: n(raw.budget),
          pools: [
            [n(raw.pools[0][0]), n(raw.pools[0][1])],
            [n(raw.pools[1][0]), n(raw.pools[1][1])],
          ],
          netPot: n(raw.netPot),
          mine: stakes
            ? [
                [n(stakes[0][0]), n(stakes[0][1])],
                [n(stakes[1][0]), n(stakes[1][1])],
              ]
            : [
                [0, 0],
                [0, 0],
              ],
          claimable: n(userR.data?.[i * 3 + 1]?.result as bigint | undefined),
          claimed: Boolean(userR.data?.[i * 3 + 2]?.result),
        },
      ];
    });
  }, [ids, marketsR.data, userR.data]);

  const refresh = useCallback(() => {
    core.refetch();
    marketsR.refetch();
    userR.refetch();
    balanceR.refetch();
    allowanceR.refetch();
  }, [core, marketsR, userR, balanceR, allowanceR]);

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
        const msg = e instanceof Error ? (e as { shortMessage?: string }).shortMessage ?? e.message.split("\n")[0] : String(e);
        setError(msg.length > 180 ? `${msg.slice(0, 180)}…` : msg);
        return undefined;
      } finally {
        setPending(null);
      }
    },
    [chainId, client, refresh, switchChain],
  );

  /** Approves enough IMD for `amount`, if the allowance is short. */
  const ensureAllowance = useCallback(
    async (amount: bigint) => {
      const current = (allowanceR.data as bigint | undefined) ?? 0n;
      if (current >= amount) return true;
      const r = await run("Approving IMD", () =>
        write({ address: IMD, abi: erc20Abi, functionName: "approve", args: [C, amount], chainId: chain.id }),
      );
      return Boolean(r);
    },
    [allowanceR.data, run, write],
  );

  const actions: Actions = {
    stake: async (id, world, side, amount) => {
      const wei = parseEther(amount.toString());
      if (!(await ensureAllowance(wei))) return;
      await run("Staking", () => write({ ...base, functionName: "stake", args: [BigInt(id), world, side, wei] }));
    },
    create: async (input) => {
      const deposit = parseEther(String(RULES.creationDeposit));
      if (!(await ensureAllowance(deposit))) return undefined;
      const receipt = await run("Creating market", () =>
        write({
          ...base,
          functionName: "createMarket",
          // The last argument caps what the contract may pull: a configuration activated meanwhile that charges
          // more makes the call revert instead of taking a larger deposit.
          args: [input.condition, input.outcome, input.rules, BigInt(input.closeTime), BigInt(input.resolveTime), deposit],
        }),
      );
      for (const log of receipt?.logs ?? []) {
        try {
          const ev = decodeEventLog({ abi: conditionalsAbi, data: log.data, topics: log.topics });
          if (ev.eventName === "MarketCreated") return Number(ev.args.marketId);
        } catch {}
      }
      return undefined;
    },
    requestResolution: async (id) => {
      const m = markets.find((x) => x.id === id);
      const now = Math.floor(Date.now() / 1000);
      const extra = m ? askCost(m, now) : 0;
      if (extra > 0 && !(await ensureAllowance(parseEther(extra.toString())))) return;
      await run("Paying the oracle", () => write({ ...base, functionName: "requestResolution", args: [BigInt(id)] }));
    },
    claim: async (id) => {
      await run("Claiming", () => write({ ...base, functionName: "claim", args: [BigInt(id)] }));
    },
    settle: async (id) => {
      await run("Settling", () => write({ ...base, functionName: "settle", args: [BigInt(id)] }));
    },
    voidMarket: async (id) => {
      await run("Voiding", () => write({ ...base, functionName: "voidMarket", args: [BigInt(id)] }));
    },
  };

  const totals = {
    burned: n(core.data?.[1]?.result as bigint | undefined),
    builderFees: n(core.data?.[2]?.result as bigint | undefined),
    oracleSpend: n(core.data?.[3]?.result as bigint | undefined),
    markets: count,
    staked: markets.reduce((s, m) => s + m.pools[0][0] + m.pools[0][1] + m.pools[1][0] + m.pools[1][1], 0),
  };

  return {
    live: true,
    ready: core.isSuccess && (ids.length === 0 || marketsR.isSuccess),
    markets,
    totals,
    account: address,
    connected: isConnected,
    wrongChain: isConnected && chainId !== chain.id,
    connect: () => {
      const c = connectors[0];
      if (c) connectWallet({ connector: c, chainId: chain.id });
      else setError("No browser wallet found. Install MetaMask or Rabby.");
    },
    disconnect: () => disconnectWallet(),
    balance: n(balanceR.data as bigint | undefined),
    actions,
    pending,
    error,
    clearError: () => setError(null),
  };
}
