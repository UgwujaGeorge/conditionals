"use client";

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { createContext, useContext, useState, type ReactNode } from "react";
import { WagmiProvider, createConfig, http } from "wagmi";
import { injected } from "wagmi/connectors";

import { chain, LIVE } from "@/lib/config";
import { useDemoMarkets } from "@/hooks/useDemoMarkets";
import { useLiveMarkets } from "@/hooks/useLiveMarkets";
import type { Source } from "@/lib/types";

const wagmiConfig = createConfig({
  chains: [chain],
  connectors: [injected()],
  transports: { [chain.id]: http() },
  ssr: true,
});

// LIVE is fixed at build time, so the same hook runs on every render.
const useSource = LIVE ? useLiveMarkets : useDemoMarkets;

const SourceContext = createContext<Source | null>(null);

function Bridge({ children }: { children: ReactNode }) {
  const source = useSource();
  return <SourceContext.Provider value={source}>{children}</SourceContext.Provider>;
}

export function Providers({ children }: { children: ReactNode }) {
  const [queryClient] = useState(() => new QueryClient());
  return (
    <WagmiProvider config={wagmiConfig}>
      <QueryClientProvider client={queryClient}>
        <Bridge>{children}</Bridge>
      </QueryClientProvider>
    </WagmiProvider>
  );
}

export function useMarkets() {
  const ctx = useContext(SourceContext);
  if (!ctx) throw new Error("useMarkets outside Providers");
  return ctx;
}
