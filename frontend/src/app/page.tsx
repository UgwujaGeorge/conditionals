"use client";

import { useCallback, useEffect, useState } from "react";

import { CreateModal } from "@/components/CreateModal";
import { Featured } from "@/components/Featured";
import { Header } from "@/components/Header";
import { Hero } from "@/components/Hero";
import { MarketDrawer } from "@/components/MarketDrawer";
import { Markets } from "@/components/Markets";
import { Footer, HowItWorks, ImdSection, Toast } from "@/components/Sections";
import { Stats } from "@/components/Stats";
import { useNow } from "@/hooks/useNow";

/** A market opens in the drawer from its hash, #m-<id>, so links to a market can be shared. */
function useHashMarket() {
  const [id, setId] = useState<number | null>(null);
  useEffect(() => {
    const read = () => {
      const m = window.location.hash.match(/^#m-(\d+)$/);
      setId(m ? Number(m[1]) : null);
    };
    read();
    window.addEventListener("hashchange", read);
    return () => window.removeEventListener("hashchange", read);
  }, []);
  const close = useCallback(() => {
    history.pushState(null, "", window.location.pathname + window.location.search);
    setId(null);
  }, []);
  const open = useCallback((n: number) => {
    window.location.hash = `m-${n}`;
  }, []);
  return [id, open, close] as const;
}

export default function Home() {
  const now = useNow();
  const [marketId, openMarket, closeMarket] = useHashMarket();
  const [creating, setCreating] = useState(false);
  const create = useCallback(() => setCreating(true), []);

  return (
    <>
      <Header onCreate={create} />
      <main>
        <Hero onCreate={create} />
        <div className="relative -mt-2 pt-12">
          <Stats />
        </div>
        <Featured now={now} />
        <Markets now={now} onCreate={create} />
        <HowItWorks />
        <ImdSection />
      </main>
      <Footer />
      <MarketDrawer id={marketId} now={now} onClose={closeMarket} />
      <CreateModal
        open={creating}
        now={now}
        onClose={() => setCreating(false)}
        onCreated={(id) => {
          setCreating(false);
          openMarket(id);
        }}
      />
      <Toast />
    </>
  );
}
