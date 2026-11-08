"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useMemo, useState, type ReactNode } from "react";

import { Header } from "../Header";
import { useFacts } from "../Providers";
import { Footer } from "../Sections";
import { AddFact } from "./AddFact";
import { chanceShown, FactCard } from "./FactCard";
import { slugify, stance, type FactView } from "@/lib/facts";
import { fmtPct } from "@/lib/format";

type Block = { kind: "h" | "p"; text: string };
type Article = { blocks: Block[]; by: "ai" | "plain"; writtenAt: number };

function Shell({ children }: { children: ReactNode }) {
  return (
    <>
      <Header />
      <main className="mx-auto min-h-[70svh] max-w-5xl px-4 pt-28 sm:px-6">{children}</main>
      <Footer />
      <FactsToast />
    </>
  );
}

function FactsToast() {
  const { pending, error, clearError } = useFacts();
  if (!pending && !error) return null;
  return (
    <div className="fixed inset-x-0 bottom-5 z-[70] flex justify-center px-4">
      <div className={`panel flex max-w-lg items-center gap-3 !rounded-full px-5 py-3 text-sm ${error ? "!border-sun/40" : ""}`}>
        <span className={`h-2 w-2 rounded-full ${pending ? "animate-pulse-slow bg-moon" : "bg-sun"}`} />
        <span className="line-clamp-2 text-ink-2">{pending ? `${pending}…` : error}</span>
        {error && (
          <button onClick={clearError} className="ml-2 text-mute hover:text-ink">
            ✕
          </button>
        )}
      </div>
    </div>
  );
}

function SampleNote() {
  const { live } = useFacts();
  if (live) return null;
  return (
    <p className="mt-4 inline-flex items-center gap-2 rounded-full border border-sun/30 bg-sun/5 px-3 py-1.5 text-xs text-sun">
      Preview: these are sample facts and a sample wallet. Fact markets open when their contract goes live.
    </p>
  );
}

function OwedBar() {
  const { owed, actions, pending } = useFacts();
  if (owed <= 0) return null;
  return (
    <div className="panel mt-6 flex flex-wrap items-center gap-3 px-5 py-3 text-sm">
      <span className="text-ink-2">Fees and seed returns from facts you seeded: {owed.toFixed(4)} IMD</span>
      <button disabled={Boolean(pending)} onClick={actions.withdraw} className="btn btn-ghost ml-auto !py-1.5 text-sm">
        Withdraw
      </button>
    </div>
  );
}

type Page = { slug: string; topic: string; facts: FactView[] };

function pagesOf(facts: FactView[]): Page[] {
  const map = new Map<string, Page>();
  for (const f of facts) {
    const slug = slugify(f.topic);
    if (!slug) continue;
    const page = map.get(slug) ?? { slug, topic: f.topic, facts: [] };
    page.facts.push(f);
    map.set(slug, page);
  }
  return [...map.values()].sort((a, b) => b.facts.length - a.facts.length || a.topic.localeCompare(b.topic));
}

/** /wiki: every page, a search, and a form to start a page. */
export function WikiIndex() {
  const { facts, ready } = useFacts();
  const router = useRouter();
  const [query, setQuery] = useState("");
  const pages = useMemo(() => pagesOf(facts), [facts]);
  const shown = pages.filter(
    (p) => !query || p.topic.toLowerCase().includes(query.toLowerCase()) || p.facts.some((f) => f.claim.toLowerCase().includes(query.toLowerCase())),
  );
  const judged = facts.filter((f) => f.verdict !== 0).length;

  return (
    <Shell>
      <p className="eyebrow">Conditionals encyclopedia</p>
      <h1 className="mt-3 font-display text-[clamp(2.6rem,6vw,4.6rem)] leading-[1.02]">
        Every fact is a <span className="text-split-grad italic">market</span>.
      </h1>
      <p className="mt-5 max-w-2xl text-lg leading-relaxed text-ink-2">
        Instead of editors deciding what is true, every statement here trades as TRUE or FALSE. The odds never close.
        Anyone who thinks they are wrong can have the IMD swarm judge the fact, and the market pays whoever was right.
        Each page is written by AI from the current odds.
      </p>
      <SampleNote />
      <OwedBar />

      <div className="mt-10 grid gap-3 sm:grid-cols-3">
        {[
          ["Pages", pages.length],
          ["Facts traded", facts.length],
          ["Judged by the swarm", judged],
        ].map(([label, value]) => (
          <div key={label} className="panel px-5 py-4">
            <p className="eyebrow">{label}</p>
            <p className="num mt-2 text-2xl">{ready ? value : "…"}</p>
          </div>
        ))}
      </div>

      <div className="mt-12 flex flex-wrap items-end justify-between gap-4">
        <h2 className="font-display text-3xl">Pages</h2>
        <input className="field !w-full max-w-xs !py-2" placeholder="Search pages and facts" value={query} onChange={(e) => setQuery(e.target.value)} />
      </div>
      <div className="mt-5 grid gap-3 sm:grid-cols-2">
        {shown.map((p) => {
          const top = [...p.facts].sort((a, b) => Math.abs(chanceShown(b) - 0.5) - Math.abs(chanceShown(a) - 0.5))[0];
          const disputed = p.facts.filter((f) => stance(chanceShown(f)) === "disputed").length;
          return (
            <Link key={p.slug} href={`/wiki/${p.slug}`} className="panel group block p-5 transition hover:border-line-2">
              <div className="flex items-baseline justify-between gap-3">
                <h3 className="font-display text-2xl group-hover:text-sun">{p.topic}</h3>
                <span className="text-xs text-mute">
                  {p.facts.length} {p.facts.length === 1 ? "fact" : "facts"}
                  {disputed ? ` · ${disputed} disputed` : ""}
                </span>
              </div>
              {top && (
                <p className="mt-3 line-clamp-2 text-sm text-ink-2">
                  <span className="num text-ink">{fmtPct(chanceShown(top))}</span> {top.claim}
                </p>
              )}
            </Link>
          );
        })}
        {ready && shown.length === 0 && <p className="text-sm text-mute">No page matches. Start one below.</p>}
      </div>

      <h2 id="start" className="mt-16 scroll-mt-24 font-display text-3xl">
        Start a page
      </h2>
      <p className="mt-2 max-w-2xl text-sm text-ink-2">
        Add a fact under a new or existing page name. You seed its market and earn half of every trading fee on it.
      </p>
      <div className="mt-5">
        <AddFact onAdded={(slug) => router.push(`/wiki/${slug}`)} />
      </div>

      <div className="panel mt-16 p-5 text-sm leading-relaxed text-ink-2 sm:p-6">
        <h2 className="font-display text-2xl text-ink">For other prediction markets</h2>
        <p className="mt-2">
          Every fact, its odds and the swarm&apos;s latest verdict are free to read as JSON, for use as a resolution
          source or a reference in any market:
        </p>
        <p className="num mt-3 break-all text-xs text-ink">
          GET https://conditionals.xyz/api/facts · /api/facts?topic=bitcoin · /api/wiki/bitcoin
        </p>
      </div>
    </Shell>
  );
}

function ArticleView({ slug, topic }: { slug: string; topic: string }) {
  const [article, setArticle] = useState<Article | null>(null);
  const [failed, setFailed] = useState(false);
  useEffect(() => {
    let alive = true;
    fetch(`/api/wiki/${slug}`)
      .then((r) => (r.ok ? r.json() : Promise.reject()))
      .then((d: { article: Article }) => alive && setArticle(d.article))
      .catch(() => alive && setFailed(true));
    return () => {
      alive = false;
    };
  }, [slug]);

  return (
    <section className="panel mt-8 p-6 sm:p-8">
      <div className="flex flex-wrap items-center gap-2">
        <span className="chip">{article?.by === "ai" ? "Written by AI from the market odds" : "Written from the market odds"}</span>
        {article && <span className="text-xs text-dim">Updated {new Date(article.writtenAt).toLocaleString("en-US", { dateStyle: "medium", timeStyle: "short" })}</span>}
      </div>
      <div className="mt-5 grid gap-4 text-[1.02rem] leading-relaxed text-ink-2">
        {!article && !failed && <p className="animate-pulse text-mute">Writing the {topic} page from the current odds…</p>}
        {failed && <p className="text-mute">The page text could not be written just now. The facts below are live.</p>}
        {article?.blocks.map((b, i) =>
          b.kind === "h" ? (
            <h2 key={i} className="mt-2 font-display text-2xl text-ink">
              {b.text}
            </h2>
          ) : (
            <p key={i}>{b.text}</p>
          ),
        )}
      </div>
    </section>
  );
}

/** /wiki/[slug]: the article, every fact on the page, and a form to add one. */
export function WikiPage({ slug }: { slug: string }) {
  const { facts, ready } = useFacts();
  const list = useMemo(
    () => facts.filter((f) => slugify(f.topic) === slug).sort((a, b) => a.id - b.id),
    [facts, slug],
  );
  const topic = list[0]?.topic;

  if (ready && !topic) {
    return (
      <Shell>
        <p className="eyebrow">Conditionals encyclopedia</p>
        <h1 className="mt-3 font-display text-5xl">No page yet</h1>
        <p className="mt-4 text-ink-2">Nobody has added a fact under this name. Be the first.</p>
        <Link href="/wiki#start" className="btn btn-primary mt-6">
          Start a page
        </Link>
      </Shell>
    );
  }

  return (
    <Shell>
      <Link href="/wiki" className="eyebrow hover:text-ink">
        ← Encyclopedia
      </Link>
      <h1 className="mt-3 font-display text-[clamp(2.6rem,6vw,4.4rem)] leading-none">{topic ?? "…"}</h1>
      <SampleNote />
      <OwedBar />
      {topic && <ArticleView slug={slug} topic={topic} />}

      <h2 className="mt-12 font-display text-3xl">The facts</h2>
      <p className="mt-2 max-w-2xl text-sm text-ink-2">
        Each fact trades nonstop. If you think the odds are wrong, buy the side you believe, or ask the swarm to judge it
        now: that round pays the side the swarm picks.
      </p>
      <div className="mt-5 grid gap-4">
        {list.map((f) => (
          <FactCard key={f.id} fact={f} />
        ))}
      </div>

      {topic && (
        <>
          <h2 className="mt-14 font-display text-3xl">Add a fact to {topic}</h2>
          <div className="mt-5">
            <AddFact topic={topic} />
          </div>
        </>
      )}
    </Shell>
  );
}
