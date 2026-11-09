"use client";

import { useState } from "react";
import { useConnection } from "wagmi";

import { Header } from "./Header";
import { Footer } from "./Sections";
import data from "@/data/airdrop-1.json";
import { LINKS } from "@/lib/config";
import { fmtImd, short } from "@/lib/format";

const tx = (hash: string) => `${LINKS.explorer}/tx/${hash}`;

/** The record of each airdrop: who qualified, what they got, and the transaction that paid them. */
export function AirdropPage() {
  const { address } = useConnection();
  const [query, setQuery] = useState("");
  const lookup = (query.trim() || address || "").toLowerCase();
  const mine = lookup ? data.recipients.find((r) => r.address.toLowerCase() === lookup) : undefined;
  const rows = [...data.recipients].sort((a, b) => Number(b.imd) - Number(a.imd));

  return (
    <>
      <Header />
      <main className="mx-auto min-h-[70svh] max-w-5xl px-4 pt-28 sm:px-6">
        <p className="eyebrow">Airdrop</p>
        <h1 className="mt-3 font-display text-[clamp(2.6rem,6vw,4.4rem)] leading-none">Friends of the Swarm</h1>
        <p className="mt-5 max-w-2xl text-lg leading-relaxed text-ink-2">
          {fmtImd(Number(data.totalImd))} IMD sent to {data.recipients.length} CONDITION holders. {data.rule}
        </p>
        <p className="mt-2 text-sm text-mute">
          Snapshot at Robinhood Chain block {data.snapshotBlock.toLocaleString("en-US")}. The IMD was bought on the
          IMD/ETH pool in{" "}
          <a href={tx(data.swapTx)} target="_blank" rel="noreferrer" className="underline hover:text-ink">
            this swap
          </a>
          .
        </p>

        <div className="panel mt-8 grid gap-3 p-5 sm:p-6">
          <label className="text-sm text-ink-2" htmlFor="lookup">
            Check a wallet
          </label>
          <input
            id="lookup"
            className="field num"
            placeholder={address ?? "0x…"}
            value={query}
            onChange={(e) => setQuery(e.target.value)}
          />
          {lookup &&
            (mine ? (
              <p className="text-good">
                {short(mine.address)} received {fmtImd(Number(mine.imd), 4)} IMD for {fmtImd(Number(mine.condition), 0)}{" "}
                CONDITION.{" "}
                <a href={tx(mine.tx)} target="_blank" rel="noreferrer" className="underline">
                  View transaction
                </a>
              </p>
            ) : (
              <p className="text-mute">This wallet was not in this airdrop.</p>
            ))}
        </div>

        <div className="panel mt-8 overflow-x-auto">
          <table className="w-full min-w-[34rem] text-sm">
            <thead className="text-left text-mute">
              <tr>
                <th className="px-5 py-3 font-normal">Wallet</th>
                <th className="px-5 py-3 text-right font-normal">CONDITION held</th>
                <th className="px-5 py-3 text-right font-normal">IMD received</th>
                <th className="px-5 py-3 text-right font-normal">Transaction</th>
              </tr>
            </thead>
            <tbody className="num">
              {rows.map((r) => (
                <tr key={r.address} className="border-t border-line">
                  <td className="px-5 py-2.5">{short(r.address)}</td>
                  <td className="px-5 py-2.5 text-right">{fmtImd(Number(r.condition), 0)}</td>
                  <td className="px-5 py-2.5 text-right text-ink">{fmtImd(Number(r.imd), 4)}</td>
                  <td className="px-5 py-2.5 text-right">
                    <a href={tx(r.tx)} target="_blank" rel="noreferrer" className="text-ink-2 underline hover:text-ink">
                      {r.tx.slice(0, 10)}…
                    </a>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </main>
      <Footer />
    </>
  );
}
