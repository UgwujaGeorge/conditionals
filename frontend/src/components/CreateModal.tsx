"use client";

import { useEffect, useMemo, useState } from "react";
import { AnimatePresence, motion } from "motion/react";

import { useMarkets } from "./Providers";
import { ForkGlyph, OracleIcon } from "./Glyphs";
import { RULES } from "@/lib/config";
import type { MarketView } from "@/lib/types";

/** The contract's text rule: printable ASCII without `"` or `\`. */
const VALID = /^[\x20-\x21\x23-\x5b\x5d-\x7e]*$/;

function textError(v: string, max: number, name: string) {
  if (!v.trim()) return `${name} is required.`;
  if (v.length > max) return `${name} is ${v.length} characters; the limit is ${max}.`;
  if (!VALID.test(v)) return `${name} must be plain ASCII, without double quotes, backslashes or line breaks.`;
  return null;
}

const toLocalInput = (unix: number) => {
  const d = new Date(unix * 1000);
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
};
const fromLocalInput = (v: string) => Math.floor(new Date(v).getTime() / 1000);

const EXAMPLES = [
  {
    condition: "The Clarity Act is signed into US law by 2026-12-31",
    outcome: "ETH closes above 5000 USD on Coinbase on 2027-01-15",
    rules: "Law: congress.gov bill status shows Became Law. Price: the Coinbase ETH-USD daily close (UTC) on 2027-01-15.",
  },
  {
    condition: "The Federal Reserve cuts rates at its December 2026 FOMC meeting",
    outcome: "BTC closes above 150000 USD on Coinbase on 2027-01-31",
    rules: "Rate decision: the FOMC statement on federalreserve.gov. Price: the Coinbase BTC-USD daily close (UTC).",
  },
];

type Check = { ok: boolean; blockers: { code: string; detail: string }[]; suggestions: { code: string; detail: string }[]; error: string | null };

export function CreateModal({ open, onClose, onCreated, now }: { open: boolean; onClose: () => void; onCreated: (id: number) => void; now: number }) {
  const src = useMarkets();
  const [condition, setCondition] = useState("");
  const [outcome, setOutcome] = useState("");
  const [rules, setRules] = useState("");
  const [closeInput, setClose] = useState("");
  const [resolveInput, setResolve] = useState("");
  // Until edited, trading closes in 14 days and the market is judged in 60.
  const close = closeInput || (now ? toLocalInput(now + 14 * 86_400) : "");
  const resolve = resolveInput || (now ? toLocalInput(now + 60 * 86_400) : "");
  const [check, setCheck] = useState<Check | null>(null);
  const [checking, setChecking] = useState(false);

  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && onClose();
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [open, onClose]);

  const closeTime = close ? fromLocalInput(close) : 0;
  const resolveTime = resolve ? fromLocalInput(resolve) : 0;

  const errors = useMemo(() => {
    const e: string[] = [];
    const a = textError(condition, RULES.maxCondition, "The condition");
    const b = textError(outcome, RULES.maxOutcome, "The outcome");
    const c = textError(rules, RULES.maxRules, "The rules");
    [a, b, c].forEach((x) => x && e.push(x));
    if (!c && !rules.includes(" ")) e.push("The rules need at least one space.");
    if (closeTime && closeTime <= now) e.push("Trading must close in the future.");
    if (closeTime && resolveTime && resolveTime < closeTime) e.push("The resolve time must be at or after the close.");
    if (resolveTime && resolveTime > now + 730 * 86_400) e.push("The resolve time must be within two years.");
    return e;
  }, [condition, outcome, rules, closeTime, resolveTime, now]);

  const preview: MarketView = {
    id: 0,
    creator: "",
    condition,
    outcome,
    rules,
    closeTime,
    resolveTime,
    voidAfter: 0,
    status: "open",
    world: 0,
    winningSide: 0,
    worldRefunded: false,
    answers: [0, 0],
    openAsks: [0, 0],
    lastAskAt: [0, 0],
    budget: 1,
    pools: [
      [1, 1],
      [1, 1],
    ],
    netPot: 0,
    mine: [
      [0, 0],
      [0, 0],
    ],
    claimable: 0,
    claimed: false,
  };

  const question = (q: "condition" | "outcome", text: string) =>
    `Conditionals market N on Robinhood Chain contract 0x…, ${q} statement. Was the following statement true as of unix time ${resolveTime || "…"} (UTC)? Statement: ${text || "…"}`;

  const runCheck = async () => {
    setChecking(true);
    setCheck(null);
    try {
      const [a, b] = await Promise.all(
        [question("condition", condition), question("outcome", outcome)].map((qq) =>
          fetch("/api/check", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ question: qq }) }).then(
            (r) => r.json() as Promise<Check>,
          ),
        ),
      );
      setCheck({
        ok: a.ok && b.ok,
        blockers: [...(a.blockers ?? []), ...(b.blockers ?? [])],
        suggestions: [...(a.suggestions ?? []), ...(b.suggestions ?? [])].filter((s) => s.code !== "not_answerable"),
        error: a.error ?? b.error,
      });
    } catch {
      setCheck({ ok: false, blockers: [], suggestions: [], error: "Could not reach the IMD API." });
    } finally {
      setChecking(false);
    }
  };

  const submit = async () => {
    const id = await src.actions.create({ condition: condition.trim(), outcome: outcome.trim(), rules: rules.trim(), closeTime, resolveTime });
    if (id) {
      setCondition("");
      setOutcome("");
      setRules("");
      setCheck(null);
      onCreated(id);
    }
  };

  return (
    <AnimatePresence>
      {open && (
        <motion.div className="fixed inset-0 z-50 flex items-end justify-center sm:items-center" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}>
          <button aria-label="Close" className="absolute inset-0 bg-black/75 backdrop-blur-sm" onClick={onClose} />
          <motion.div
            role="dialog"
            aria-modal
            className="relative max-h-[94svh] w-full max-w-5xl overflow-y-auto rounded-t-[28px] border border-line bg-bg-2 scrollbar-none sm:rounded-[28px]"
            initial={{ y: 40, opacity: 0, scale: 0.98 }}
            animate={{ y: 0, opacity: 1, scale: 1 }}
            exit={{ y: 40, opacity: 0, scale: 0.98 }}
            transition={{ type: "spring", stiffness: 280, damping: 30 }}
          >
            <div className="grid lg:grid-cols-[1.25fr_1fr]">
              <div className="p-6 sm:p-9">
                <div className="flex items-start justify-between gap-4">
                  <div>
                    <p className="eyebrow">New market</p>
                    <h2 className="mt-2 font-display text-4xl leading-none sm:text-5xl">
                      Open a <em className="text-split-grad">fork.</em>
                    </h2>
                  </div>
                  <button onClick={onClose} className="btn btn-ghost !h-9 !w-9 !p-0" aria-label="Close">
                    <svg viewBox="0 0 24 24" className="h-4 w-4" fill="none">
                      <path d="M6 6l12 12M18 6 6 18" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" />
                    </svg>
                  </button>
                </div>

                <div className="mt-5 flex flex-wrap gap-2">
                  {EXAMPLES.map((ex) => (
                    <button
                      key={ex.condition}
                      onClick={() => {
                        setCondition(ex.condition);
                        setOutcome(ex.outcome);
                        setRules(ex.rules);
                        setCheck(null);
                      }}
                      className="chip !normal-case !tracking-normal hover:text-ink"
                    >
                      Try: {ex.condition.slice(0, 34)}…
                    </button>
                  ))}
                </div>

                <Field label="If" hint="The event the market is conditional on" tone="sun" count={`${condition.length}/${RULES.maxCondition}`}>
                  <textarea
                    rows={2}
                    value={condition}
                    onChange={(e) => {
                      setCondition(e.target.value);
                      setCheck(null);
                    }}
                    placeholder="The Clarity Act is signed into US law by 2026-12-31"
                    className="field resize-none"
                  />
                </Field>
                <Field label="Will" hint="What traders predict, in both worlds" count={`${outcome.length}/${RULES.maxOutcome}`}>
                  <textarea
                    rows={2}
                    value={outcome}
                    onChange={(e) => {
                      setOutcome(e.target.value);
                      setCheck(null);
                    }}
                    placeholder="ETH closes above 5000 USD on Coinbase on 2027-01-15"
                    className="field resize-none"
                  />
                </Field>
                <Field label="Rules" hint="How the oracle should judge both, and which sources to use" count={`${rules.length}/${RULES.maxRules}`}>
                  <textarea
                    rows={3}
                    value={rules}
                    onChange={(e) => {
                      setRules(e.target.value);
                      setCheck(null);
                    }}
                    placeholder="Law: congress.gov shows Became Law. Price: the Coinbase ETH-USD daily close (UTC)."
                    className="field resize-none"
                  />
                </Field>
                <div className="mt-5 grid gap-4 sm:grid-cols-2">
                  <label className="block">
                    <span className="eyebrow">Trading closes</span>
                    <input type="datetime-local" value={close} onChange={(e) => setClose(e.target.value)} className="field mt-2 [color-scheme:dark]" />
                  </label>
                  <label className="block">
                    <span className="eyebrow">Judged as of</span>
                    <input type="datetime-local" value={resolve} onChange={(e) => setResolve(e.target.value)} className="field mt-2 [color-scheme:dark]" />
                  </label>
                </div>

                <p className="mt-3 text-xs text-mute">
                  Close trading before the condition or the outcome can be known: stakes are accepted until then.
                </p>

                {errors.length > 0 && (condition || outcome || rules) && (
                  <ul className="mt-5 space-y-1 text-sm text-sun">
                    {errors.map((e) => (
                      <li key={e}>· {e}</li>
                    ))}
                  </ul>
                )}
              </div>

              <div className="relative border-t border-line bg-black/25 p-6 sm:p-9 lg:border-l lg:border-t-0">
                <p className="eyebrow">Preview</p>
                <div className="mt-4 -mx-2">
                  <ForkGlyph m={preview} height={130} />
                </div>
                <div className="mt-2 grid grid-cols-2 gap-2 text-xs">
                  <div className="rounded-xl border border-sun/30 bg-sun/[0.05] p-3">
                    <p className="eyebrow !text-[0.58rem] !text-sun">World A</p>
                    <p className="mt-1 text-ink-2">{condition ? "it happens" : "…"}</p>
                  </div>
                  <div className="rounded-xl border border-moon/30 bg-moon/[0.05] p-3">
                    <p className="eyebrow !text-[0.58rem] !text-moon">World B</p>
                    <p className="mt-1 text-ink-2">{condition ? "it doesn't" : "…"}</p>
                  </div>
                </div>

                <div className="mt-6 rounded-2xl border border-line p-4">
                  <div className="flex items-center gap-2">
                    <OracleIcon className="h-4 w-4 text-moon" />
                    <p className="eyebrow">What the oracle will be asked</p>
                  </div>
                  <p className="mt-3 text-xs leading-relaxed text-ink-2">{question("condition", condition)}</p>
                  <p className="mt-2 text-xs leading-relaxed text-ink-2">{question("outcome", outcome)}</p>
                  <button onClick={runCheck} disabled={checking || !condition || !outcome} className="btn btn-ghost mt-4 w-full !py-2.5 text-sm">
                    {checking ? "Checking with IMD…" : "Run IMD's free pre-check"}
                  </button>
                  {check && (
                    <div className="mt-3 text-xs">
                      {check.error ? (
                        <p className="text-sun">{check.error}</p>
                      ) : check.blockers.length === 0 ? (
                        <p className="text-good">The oracle accepts both questions.</p>
                      ) : (
                        check.blockers.map((b) => (
                          <p key={b.code} className="text-sun">
                            {b.code}: {b.detail}
                          </p>
                        ))
                      )}
                      {check.suggestions.map((s) => (
                        <p key={s.code} className="mt-1 text-mute">
                          {s.detail}
                        </p>
                      ))}
                    </div>
                  )}
                </div>

                <div className="mt-6 space-y-2 text-sm">
                  <div className="flex justify-between">
                    <span className="text-mute">Oracle deposit</span>
                    <span className="num">{RULES.creationDeposit} IMD</span>
                  </div>
                  <p className="text-xs text-mute">
                    Pays for the two oracle questions ({RULES.oraclePrice} IMD each, to the IMD swarm). Anything unspent comes
                    back to you.
                  </p>
                </div>

                <button
                  onClick={() => (src.connected ? submit() : src.connect())}
                  disabled={src.connected && (errors.length > 0 || Boolean(src.pending))}
                  className="btn btn-primary mt-6 w-full !py-4 text-base"
                >
                  {!src.connected ? "Connect wallet" : src.pending ?? `Create market · ${RULES.creationDeposit} IMD`}
                </button>
              </div>
            </div>
          </motion.div>
        </motion.div>
      )}
    </AnimatePresence>
  );
}

function Field({
  label,
  hint,
  count,
  tone,
  children,
}: {
  label: string;
  hint: string;
  count: string;
  tone?: "sun";
  children: React.ReactNode;
}) {
  return (
    <label className="mt-5 block">
      <span className="flex items-baseline justify-between gap-3">
        <span>
          <span className={`font-display text-2xl italic ${tone === "sun" ? "text-sun" : "text-ink"}`}>{label}</span>
          <span className="ml-3 text-xs text-mute">{hint}</span>
        </span>
        <span className="num text-[0.68rem] text-dim">{count}</span>
      </span>
      <span className="mt-2 block">{children}</span>
    </label>
  );
}
