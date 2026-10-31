import { defineChain, type Address } from "viem";

export const robinhood = defineChain({
  id: 4663,
  name: "Robinhood Chain",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: { default: { http: [process.env.NEXT_PUBLIC_RPC_URL ?? "https://rpc.mainnet.chain.robinhood.com"] } },
  blockExplorers: { default: { name: "Blockscout", url: "https://robinhoodchain.blockscout.com" } },
});

export const chain = robinhood;

const env = (v: string | undefined) => (v && v.startsWith("0x") && v.length === 42 ? (v as Address) : undefined);

/** Set once the IMD launch is live. Without them, or with NEXT_PUBLIC_DEMO=1, the site runs on sample markets. */
const DEPLOYED: Address | undefined = "0xd8e4baf371abc9a36611543386f68e0df122fcf0";
const DEPLOYED_ZAP: Address | undefined = "0x750a28557a6263681f0cb9612cc86cc6f3a7476d";

const demo = process.env.NEXT_PUBLIC_DEMO === "1";

export const ADDRESSES = {
  conditionals: demo ? undefined : (env(process.env.NEXT_PUBLIC_CONDITIONALS_ADDRESS) ?? DEPLOYED),
  zap: demo ? undefined : (env(process.env.NEXT_PUBLIC_ZAP_ADDRESS) ?? DEPLOYED_ZAP),
  usdg: "0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168" as Address,
  poolManager: "0x8366a39CC670B4001A1121B8F6A443A643e40951" as Address,
  imd: env(process.env.NEXT_PUBLIC_IMD_ADDRESS) ?? ("0x5f7bb59365ce557c26dbcaa4ee9d39a4b95b7127" as Address),
  intake: "0xa43e6f75ee006411f79ac1c84120606c2330de82" as Address,
  oracleSigner: "0x5598aa9146215bc13eb26f2c692ad1461fd32982" as Address,
};

export const LIVE = Boolean(ADDRESSES.conditionals);

export const LINKS = {
  imd: "https://imd.fun",
  oracle: "https://explorer.imd.fun",
  x: process.env.NEXT_PUBLIC_X_URL ?? "https://x.com/",
  github: process.env.NEXT_PUBLIC_GITHUB_URL ?? "https://github.com/UgwujaGeorge/conditionals",
  explorer: chain.blockExplorers.default.url,
};

/** Mirrors the contract's constants. */
export const RULES = {
  /** Every trade with the maker: half to the market's creator, 67/200 burned, the rest to the builder. */
  feeBps: 200,
  minStake: 0.001,
  oraclePrice: 0.5,
  oracleDeposit: 1,
  minB: 0.5,
  maxB: 100,
  panelSize: 5,
  quorum: 4,
  resolutionDays: 30,
  retryHours: 24,
  maxCondition: 280,
  maxOutcome: 280,
  maxRules: 500,
  /** The slippage a stake or an exit accepts. */
  slippage: 0.02,
};
