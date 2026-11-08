"use client";

import Link from "next/link";
import { useEffect, useState } from "react";

import { useMarkets } from "./Providers";
import { Logo } from "./Glyphs";
import { fmtImd, short } from "@/lib/format";
import { chain } from "@/lib/config";

/** The site header. On the home page the menu scrolls; elsewhere it links back to the home page's sections. */
export function Header({ onCreate, createLabel = "Create market" }: { onCreate?: () => void; createLabel?: string }) {
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
        <Link href="/" className="flex items-center gap-2.5">
          <Logo />
          <span className="font-display text-[1.45rem] leading-none tracking-tight">Conditionals</span>
        </Link>
        {!src.live && <span className="chip hidden sm:inline-flex">Demo</span>}
        <nav className="ml-4 hidden items-center gap-6 text-sm text-ink-2 md:flex">
          <Link href="/#markets" className="transition hover:text-ink">
            Markets
          </Link>
          <Link href="/wiki" className="transition hover:text-ink">
            Encyclopedia
          </Link>
          <Link href="/#suggest" className="transition hover:text-ink">
            Suggest
          </Link>
          <Link href="/#how" className="hidden transition hover:text-ink lg:inline">
            How it works
          </Link>
          <Link href="/#imd" className="transition hover:text-ink">
            IMD
          </Link>
          <Link href="/docs" className="transition hover:text-ink">
            Docs
          </Link>
        </nav>
        <div className="ml-auto flex items-center gap-2.5">
          <Link href="/wiki" className="text-sm text-ink-2 transition hover:text-ink md:hidden">
            Encyclopedia
          </Link>
          {onCreate && (
            <button onClick={onCreate} className="btn btn-ghost hidden !py-2 text-sm sm:inline-flex">
              {createLabel}
            </button>
          )}
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
