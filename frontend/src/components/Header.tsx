"use client";

import Link from "next/link";
import { useEffect, useState } from "react";

import { useMarkets } from "./Providers";
import { Logo } from "./Glyphs";
import { fmtImd, short } from "@/lib/format";
import { chain } from "@/lib/config";

export function Header({ onCreate }: { onCreate: () => void }) {
  const src = useMarkets();
  const [scrolled, setScrolled] = useState(false);

  useEffect(() => {
    const on = () => setScrolled(window.scrollY > 24);
    on();
    window.addEventListener("scroll", on, { passive: true });
    return () => window.removeEventListener("scroll", on);
  }, []);

  return (
    <header
      className={`fixed inset-x-0 top-0 z-40 transition-all duration-500 ${
        scrolled ? "border-b border-line bg-bg/70 backdrop-blur-xl" : "border-b border-transparent"
      }`}
    >
      <div className="mx-auto flex h-16 max-w-7xl items-center gap-6 px-4 sm:px-6">
        <a href="#top" className="flex items-center gap-2.5">
          <Logo />
          <span className="font-display text-[1.45rem] leading-none tracking-tight">Conditionals</span>
        </a>
        {!src.live && <span className="chip hidden sm:inline-flex">Demo</span>}
        <nav className="ml-6 hidden items-center gap-7 text-sm text-ink-2 md:flex">
          <a href="#markets" className="transition hover:text-ink">
            Markets
          </a>
          <a href="#how" className="transition hover:text-ink">
            How it works
          </a>
          <a href="#imd" className="transition hover:text-ink">
            IMD
          </a>
          <Link href="/docs" className="transition hover:text-ink">
            Docs
          </Link>
        </nav>
        <div className="ml-auto flex items-center gap-2.5">
          <Link href="/docs" className="text-sm text-ink-2 transition hover:text-ink md:hidden">
            Docs
          </Link>
          <button onClick={onCreate} className="btn btn-ghost hidden !py-2 text-sm sm:inline-flex">
            Create market
          </button>
          {src.connected ? (
            <button
              onClick={src.disconnect}
              className="btn btn-ghost !py-2 text-sm"
              title={src.live ? "Disconnect" : "Demo wallet"}
            >
              {src.wrongChain ? (
                <span className="text-sun">Switch to {chain.name}</span>
              ) : (
                <>
                  <span className="num text-ink">{fmtImd(src.balance)} IMD</span>
                  <span className="hidden text-mute sm:inline">{src.live ? short(src.account) : "demo"}</span>
                </>
              )}
            </button>
          ) : (
            <button onClick={src.connect} className="btn btn-primary !py-2 text-sm">
              Connect
            </button>
          )}
        </div>
      </div>
    </header>
  );
}
