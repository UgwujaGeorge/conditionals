"use client";

import { FlameIcon, OracleIcon } from "./Glyphs";
import { useMarkets } from "./Providers";
import { fmtImd } from "@/lib/format";
import { RULES } from "@/lib/config";

export function Stats() {
  const { totals } = useMarkets();
  const items = [
    {
      label: "IMD burned",
      value: fmtImd(totals.burned),
      hint: "2% of every settled pot",
      icon: <FlameIcon className="h-5 w-5 text-burn" />,
    },
    {
      label: "Oracle questions bought",
      value: String(Math.round(totals.oracleSpend / RULES.oraclePrice)),
      hint: `${fmtImd(totals.oracleSpend)} IMD paid to the swarm`,
      icon: <OracleIcon className="h-5 w-5 text-moon" />,
    },
    {
      label: "IMD at stake",
      value: fmtImd(totals.staked),
      hint: "across both worlds",
      icon: <span className="block h-2.5 w-2.5 rounded-full bg-sun shadow-[0_0_14px_#FFB547]" />,
    },
    {
      label: "Markets",
      value: String(totals.markets),
      hint: "each one asks the oracle twice",
      icon: <span className="block h-2.5 w-2.5 rounded-full bg-moon shadow-[0_0_14px_#7DE3FF]" />,
    },
  ];
  return (
    <section className="mx-auto max-w-7xl px-4 sm:px-6">
      <div className="grid grid-cols-2 gap-px overflow-hidden rounded-[22px] border border-line bg-line lg:grid-cols-4">
        {items.map((it) => (
          <div key={it.label} className="flex flex-col gap-3 bg-bg-2/95 p-5 sm:p-7">
            <div className="flex items-center justify-between">
              <span className="eyebrow">{it.label}</span>
              {it.icon}
            </div>
            <span className="num text-3xl tracking-tight sm:text-4xl">{it.value}</span>
            <span className="text-xs text-mute">{it.hint}</span>
          </div>
        ))}
      </div>
    </section>
  );
}
