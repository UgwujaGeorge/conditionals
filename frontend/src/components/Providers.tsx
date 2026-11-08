"use client";

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { createContext, useContext, useState, type ReactNode } from "react";
import { WagmiProvider, createConfig, http } from "wagmi";
import { injected } from "wagmi/connectors";

import { chain, FACTS_LIVE, LIVE } from "@/lib/config";
import { useDemoMarkets } from "@/hooks/useDemoMarkets";
import { useLiveMarkets } from "@/hooks/useLiveMarkets";
import { useDemoFacts } from "@/hooks/useDemoFacts";
import { useLiveFacts } from "@/hooks/useLiveFacts";
import type { FactsSource } from "@/lib/facts";
import type { Source } from "@/lib/types";

const wagmiConfig = createConfig({
  chains: [chain],
  connectors: [injected()],
  transports: { [chain.id]: http() },
  ssr: true,
});

// LIVE is fixed at build time, so the same hook runs on every render.
const useSource = LIVE ? useLiveMarkets : useDemoMarkets;
const useFactsSource = FACTS_LIVE ? useLiveFacts : useDemoFacts;

const SourceContext = createContext<Source | null>(null);
const FactsContext = createContext<FactsSource | null>(null);

function Bridge({ children }: { children: ReactNode }) {
  const source = useSource();
  const facts = useFactsSource();
  return (
    <SourceContext.Provider value={source}>
      <FactsContext.Provider value={facts}>{children}</FactsContext.Provider>
    </SourceContext.Provider>
  );
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

export function useFacts() {
  const ctx = useContext(FactsContext);
  if (!ctx) throw new Error("useFacts outside Providers");
  return ctx;
}
