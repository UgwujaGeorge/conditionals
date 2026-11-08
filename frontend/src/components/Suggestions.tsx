"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { useConnect, useConnection, useConnectors, useSignMessage } from "wagmi";

import { useFacts, useMarkets } from "./Providers";
import { chain } from "@/lib/config";
import { slugify } from "@/lib/facts";
import { short } from "@/lib/format";
import { createMessage, KIND_LABEL, SUGGEST_LIMITS, voteMessage, type Suggestion, type SuggestionKind } from "@/lib/suggest";

const nowSeconds = () => Math.floor(Date.now() / 1000);

const KINDS: { kind: SuggestionKind; label: string }[] = [
  { kind: "new", label: "A new market" },
  { kind: "market", label: "An existing market" },
  { kind: "fact", label: "An encyclopedia fact" },
];

/** Where people recommend which markets to seed with liquidity, and back each other's picks. One vote per wallet. */
export function Suggestions() {
  const { markets } = useMarkets();
  const { facts } = useFacts();
  const { address, isConnected } = useConnection();
  const connectors = useConnectors();
  const { mutate: connect } = useConnect();
  const { mutateAsync: sign } = useSignMessage();

  const [enabled, setEnabled] = useState<boolean | null>(null);
  const [list, setList] = useState<Suggestion[]>([]);
  const [kind, setKind] = useState<SuggestionKind>("new");
  const [ref, setRef] = useState("");
  const [text, setText] = useState("");
  const [busy, setBusy] = useState(false);
  const [note, setNote] = useState<{ ok: boolean; text: string } | null>(null);

  const [version, setVersion] = useState(0);
  const load = useCallback(() => setVersion((v) => v + 1), []);

  useEffect(() => {
    let alive = true;
    fetch(`/api/suggestions${address ? `?voter=${address}` : ""}`)
      .then((r) => r.json() as Promise<{ enabled?: boolean; suggestions?: Suggestion[] }>)
      .then((d) => {
        if (!alive) return;
        setEnabled(Boolean(d.enabled));
        setList(d.suggestions ?? []);
      })
      .catch(() => alive && setEnabled(false));
    return () => {
      alive = false;
    };
  }, [address, version]);

  const ensureWallet = () => {
    if (isConnected && address) return true;
    const c = connectors[0];
    if (c) connect({ connector: c, chainId: chain.id });
    else setNote({ ok: false, text: "No browser wallet found. Install MetaMask or Rabby." });
    return false;
  };

  async function post(payload: Record<string, unknown>, message: string, done: string) {
    if (!ensureWallet()) return;
    setBusy(true);
    setNote(null);
    try {
      const signature = await sign({ message });
      const r = await fetch("/api/suggestions", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ ...payload, address, signature }),
      });
      const d = (await r.json()) as { error?: string };
      if (!r.ok) setNote({ ok: false, text: d.error ?? "That did not go through." });
      else {
        setNote({ ok: true, text: done });
        load();
      }
    } catch {
      setNote({ ok: false, text: "Signing was cancelled." });
    } finally {
      setBusy(false);
    }
  }

  const refNum = kind === "new" ? null : Number(ref);
  const trimmed = text.trim();
  const valid =
    trimmed.length <= SUGGEST_LIMITS.maxText &&
    (kind === "new" ? trimmed.length >= SUGGEST_LIMITS.minIdea : Number.isInteger(refNum) && (refNum as number) > 0);

  function submit() {
    const issuedAt = nowSeconds();
    post(
      { action: "create", kind, ref: refNum, text: trimmed, issuedAt },
      createMessage(kind, refNum, trimmed, issuedAt),
      "Posted. Share it so others can back it.",
    ).then(() => setText(""));
  }

  function back(id: number) {
    const issuedAt = nowSeconds();
    post({ action: "vote", id, issuedAt }, voteMessage(id, issuedAt), "Backed.");
  }

  const title = (s: Suggestion) => {
    if (s.kind === "market") return markets.find((m) => m.id === s.ref)?.outcome ?? `Market #${s.ref}`;
    if (s.kind === "fact") return facts.find((f) => f.id === s.ref)?.claim ?? `Fact #${s.ref}`;
    return s.text;
  };
  const href = (s: Suggestion) => {
    if (s.kind === "market") return `/#m-${s.ref}`;
    if (s.kind === "fact") {
      const f = facts.find((x) => x.id === s.ref);
      return f ? `/wiki/${slugify(f.topic)}#f-${f.id}` : null;
    }
    return null;
  };

  return (
    <section id="suggest" className="mx-auto mt-36 max-w-7xl scroll-mt-24 px-4 sm:px-6">
      <p className="eyebrow">Suggest</p>
      <h2 className="mt-3 font-display text-[clamp(2.2rem,5vw,3.6rem)] leading-tight">Which markets should we seed?</h2>
      <p className="mt-4 max-w-2xl text-ink-2">
        Recommend a new market, or an existing market or fact that needs more liquidity. Back the picks you agree with.
        The most backed get seeded. Posting and backing are free: your wallet signs a message, and nothing is sent onchain.
      </p>

      <div className="mt-10 grid gap-6 lg:grid-cols-[minmax(0,5fr)_minmax(0,7fr)]">
        <div className="panel grid content-start gap-4 p-5 sm:p-6">
          <div className="flex flex-wrap gap-2">
            {KINDS.map((k) => (
              <button
                key={k.kind}
                onClick={() => setKind(k.kind)}
                className={`btn !py-1.5 text-sm ${kind === k.kind ? "btn-primary" : "btn-ghost"}`}
              >
                {k.label}
              </button>
            ))}
          </div>
          {kind === "market" && (
            <select className="field" value={ref} onChange={(e) => setRef(e.target.value)}>
              <option value="">Pick a market</option>
              {markets.map((m) => (
                <option key={m.id} value={m.id}>
                  #{m.id} · If {m.condition.slice(0, 60)}…
                </option>
              ))}
            </select>
          )}
          {kind === "fact" && (
            <select className="field" value={ref} onChange={(e) => setRef(e.target.value)}>
              <option value="">Pick a fact</option>
              {facts.map((f) => (
                <option key={f.id} value={f.id}>
                  #{f.id} · {f.topic}: {f.claim.slice(0, 60)}
                </option>
              ))}
            </select>
          )}
          <textarea
            className="field min-h-24"
            maxLength={SUGGEST_LIMITS.maxText}
            placeholder={kind === "new" ? "If [something happens], will [outcome]? Add the source to judge it by." : "Why it deserves liquidity (optional)"}
            value={text}
            onChange={(e) => setText(e.target.value.replace(/[^\x20-\x7e]/g, ""))}
          />
          <div className="flex flex-wrap items-center gap-3">
            <button disabled={!enabled || !valid || busy} onClick={submit} className="btn btn-primary !py-2 text-sm">
              {isConnected ? "Sign and post" : "Connect to post"}
            </button>
            <span className="text-xs text-mute">
              {text.length}/{SUGGEST_LIMITS.maxText} · one post per wallet per hour
            </span>
          </div>
          {note && <p className={`text-xs ${note.ok ? "text-good" : "text-sun"}`}>{note.text}</p>}
        </div>

        <div className="grid content-start gap-3">
          {enabled && list.length === 0 && <p className="panel p-6 text-sm text-mute">No suggestions yet. Be the first.</p>}
          {enabled === false && (
            <p className="panel p-6 text-sm text-mute">
              Suggestions open soon. The most backed markets and facts will show here.
            </p>
          )}
          {list.map((s) => {
            const link = href(s);
            return (
              <div key={s.id} className="panel flex items-start gap-4 p-4 sm:p-5">
                <button
                  disabled={busy || s.voted}
                  onClick={() => back(s.id)}
                  className={`flex w-14 shrink-0 flex-col items-center rounded-2xl border py-2 transition ${
                    s.voted ? "border-sun/50 text-sun" : "border-line-2 text-ink-2 hover:border-sun/50 hover:text-sun"
                  }`}
                  title={s.voted ? "You backed this" : "Back this"}
                >
                  <span aria-hidden>▲</span>
                  <span className="num text-sm">{s.votes}</span>
                </button>
                <div className="min-w-0">
                  <span className="chip">{KIND_LABEL[s.kind]}</span>
                  <p className="mt-2 text-ink">
                    {link ? (
                      <Link href={link} className="hover:text-sun">
                        {title(s)}
                      </Link>
                    ) : (
                      title(s)
                    )}
                  </p>
                  {s.kind !== "new" && s.text && <p className="mt-1 text-sm text-ink-2">{s.text}</p>}
                  <p className="mt-2 text-xs text-dim">by {short(s.author)}</p>
                </div>
              </div>
            );
          })}
        </div>
      </div>
    </section>
  );
}

/** The home page's door to the encyclopedia. */
export function EncyclopediaTeaser() {
  const { facts, live } = useFacts();
  const topics = [...new Set(facts.map((f) => f.topic))].slice(0, 6);
  return (
    <section id="encyclopedia" className="mx-auto mt-36 max-w-7xl scroll-mt-24 px-4 sm:px-6">
      <div className="panel grid gap-8 p-6 sm:p-10 lg:grid-cols-[minmax(0,7fr)_minmax(0,5fr)] lg:items-center">
        <div>
          <p className="eyebrow">New · Encyclopedia{live ? "" : " preview"}</p>
          <h2 className="mt-3 font-display text-[clamp(2.2rem,5vw,3.6rem)] leading-tight">
            An encyclopedia where every fact is a <span className="text-split-grad italic">market</span>.
          </h2>
          <p className="mt-4 max-w-xl text-ink-2">
            No editors. Each statement trades as TRUE or FALSE and never closes. Think it&apos;s wrong? Bet against it,
            or have the IMD swarm judge it and get paid for being right. Every page is written by AI from the current odds.
          </p>
          <Link href="/wiki" className="btn btn-primary mt-7">
            Open the encyclopedia
          </Link>
        </div>
        <div className="flex flex-wrap gap-2">
          {topics.map((t) => (
            <Link
              key={t}
              href={`/wiki/${slugify(t)}`}
              className="chip !px-3 !py-1.5 !text-xs hover:!text-ink"
            >
              {t}
            </Link>
          ))}
        </div>
      </div>
    </section>
  );
}
