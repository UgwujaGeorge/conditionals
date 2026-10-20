import { defineChain, type Address } from "viem";

export const robinhood = defineChain({
  id: 4663,
  name: "Robinhood Chain",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: { default: { http: ["https://rpc.mainnet.chain.robinhood.com"] } },
  blockExplorers: { default: { name: "Blockscout", url: "https://robinhoodchain.blockscout.com" } },
});

export const chain = robinhood;

const env = (v: string | undefined) => (v && v.startsWith("0x") && v.length === 42 ? (v as Address) : undefined);

/** Set once the IMD launch is live. Without it, or with NEXT_PUBLIC_DEMO=1, the site runs on sample markets. */
const DEPLOYED: Address | undefined = undefined;

const demo = process.env.NEXT_PUBLIC_DEMO === "1";

export const ADDRESSES = {
  conditionals: demo ? undefined : (env(process.env.NEXT_PUBLIC_CONDITIONALS_ADDRESS) ?? DEPLOYED),
  imd: env(process.env.NEXT_PUBLIC_IMD_ADDRESS) ?? ("0x5f7bb59365ce557c26dbcaa4ee9d39a4b95b7127" as Address),
  intake: "0xa43e6f75ee006411f79ac1c84120606c2330de82" as Address,
  oracleSigner: "0x5598aa9146215bc13eb26f2c692ad1461fd32982" as Address,
};

export const LIVE = Boolean(ADDRESSES.conditionals);

export const LINKS = {
  imd: "https://imd.fun",
  docs: "https://imd.fun/docs/#oracle-body",
  oracle: "https://explorer.imd.fun",
  hackathon: "https://www.imdradar.site/hackathon",
  x: process.env.NEXT_PUBLIC_X_URL ?? "https://x.com/",
  github: process.env.NEXT_PUBLIC_GITHUB_URL ?? "https://github.com/UgwujaGeorge/conditionals",
  explorer: chain.blockExplorers.default.url,
};

/** Mirrors the contract's constants. */
export const RULES = {
  feeBps: 300,
  burnBps: 200,
  builderBps: 100,
  minStake: 0.001,
  oraclePrice: 0.5,
  creationDeposit: 1,
  panelSize: 5,
  quorum: 4,
  resolutionDays: 30,
  retryHours: 24,
  maxCondition: 280,
  maxOutcome: 280,
  maxRules: 500,
};
