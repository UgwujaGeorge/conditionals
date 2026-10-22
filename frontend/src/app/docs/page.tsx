import type { Metadata } from "next";
import Link from "next/link";

import { Logo } from "@/components/Glyphs";
import { ADDRESSES, LINKS } from "@/lib/config";

export const metadata: Metadata = {
  title: "Whitepaper · Conditionals",
  description: "Conditionals in plain words: prediction markets that ask \"if X happens, will Y?\"",
};

type Page = { title: string; body: React.ReactNode };

/** Each page stands on its own, so it can be shared as a single image. */
const PAGES: Page[] = [
  {
    title: "Conditionals in one line",
    body: (
      <>
        <p className="lead">
          A prediction market that asks <em className="text-split-grad">&ldquo;if X happens, will Y?&rdquo;</em>
        </p>
        <p>
          Normal prediction markets ask whether something will happen. Conditionals asks what happens next: if the
          Clarity Act passes, will ETH hit $5k? If Messi plays, will Miami win?
        </p>
        <p>You bet in IMD. The IMD oracle settles every market. It runs on Robinhood Chain.</p>
      </>
    ),
  },
  {
    title: "The problem",
    body: (
      <>
        <p>Most big questions depend on other questions.</p>
        <p>
          You might think ETH goes up <span className="text-sun">if</span> a bill passes, and down if it doesn&apos;t.
          A normal market makes you bet on ETH either way, so you can be right about ETH and still lose because the bill
          went the other way.
        </p>
        <p>
          And nobody can see the answer to the real question: <em>how much does the bill matter?</em>
        </p>
      </>
    ),
  },
  {
    title: "The idea: two worlds",
    body: (
      <>
        <p>Every market splits into two worlds:</p>
        <ul>
          <li>
            <span className="text-sun">World A</span>: X happens.
          </li>
          <li>
            <span className="text-moon">World B</span>: X doesn&apos;t happen.
          </li>
        </ul>
        <p>Each world has a YES side and a NO side for Y. You bet in the world you believe in.</p>
        <p>
          Only one world will happen. <strong>Bets in the other world are refunded in full.</strong> You never lose money
          on a world that didn&apos;t happen.
        </p>
      </>
    ),
  },
  {
    title: "How a market works",
    body: (
      <ol>
        <li>
          <strong>Create.</strong> Anyone opens a market: if X, will Y? They set when betting closes and when the answer
          is due.
        </li>
        <li>
          <strong>Bet.</strong> Put IMD on YES or NO, in World A, World B, or both.
        </li>
        <li>
          <strong>Ask.</strong> When the answer is due, the IMD oracle is asked two questions: did X happen, and did Y?
        </li>
        <li>
          <strong>Settle.</strong> The world that didn&apos;t happen is refunded. In the world that did, the winners
          take the pot.
        </li>
      </ol>
    ),
  },
  {
    title: "An example",
    body: (
      <>
        <p>
          <em>&ldquo;If the Clarity Act passes, will ETH hit $5k?&rdquo;</em>
        </p>
        <table>
          <thead>
            <tr>
              <th />
              <th>YES</th>
              <th>NO</th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <td className="text-sun">World A: it passes</td>
              <td>Alice 60</td>
              <td>Bob 40</td>
            </tr>
            <tr>
              <td className="text-moon">World B: it doesn&apos;t</td>
              <td>Carol 30</td>
              <td>Dan 70</td>
            </tr>
          </tbody>
        </table>
        <p>The crowd says: 60% if it passes, 30% if it doesn&apos;t. The Act doubles ETH&apos;s chances.</p>
        <p>
          The Act passes and ETH hits $5k. Carol and Dan get their money back. Alice wins the 100 IMD pot minus a 3%
          fee: <strong>97 IMD</strong> for her 60. Bob loses his 40.
        </p>
      </>
    ),
  },
  {
    title: "The odds are the crowd",
    body: (
      <>
        <p>There is no bookmaker setting prices. The odds come from how much money is on each side.</p>
        <p>
          60 IMD on YES and 40 on NO means the crowd thinks YES is 60% likely. Every new bet moves the odds.
        </p>
        <p>
          Put both worlds side by side and you see something no normal market shows: <strong>how much X changes Y</strong>.
          That number is useful even to people who never bet.
        </p>
      </>
    ),
  },
  {
    title: "No order book needed",
    body: (
      <>
        <p>
          On an order book, you need someone willing to take the other side of your trade at your price. Small markets
          have few traders, so prices are bad or there is no trade at all.
        </p>
        <p>
          Conditionals uses shared pots instead. Your bet goes straight into a pot, any size, at once. Everyone on the
          winning side splits the losing side&apos;s money in proportion to what they put in.
        </p>
        <p>A market works with two people. It works with two thousand.</p>
      </>
    ),
  },
  {
    title: "Who decides the answer",
    body: (
      <>
        <p>
          The <strong>IMD oracle</strong>: a panel of 5 independent AI agents that read the question and check the
          facts. At least 4 must agree.
        </p>
        <p>
          The market pays the oracle itself, from a small deposit the creator puts down. The answer comes back signed,
          and the market checks the signature before it accepts it. Nobody can type in a fake answer.
        </p>
        <p>
          If the oracle can&apos;t answer, anyone can ask again. If there is still no answer 30 days later, everyone is
          refunded.
        </p>
      </>
    ),
  },
  {
    title: "Fees",
    body: (
      <>
        <p>One fee, only on the winning world: 3% of its pot.</p>
        <ul>
          <li>
            <span className="text-burn">2% is burned</span>, removed from IMD&apos;s supply forever.
          </li>
          <li>1% goes to the builder.</li>
        </ul>
        <p>
          No fee on refunds. No fee on a world where everyone bet the same side. The fee is never more than what the
          losers put in, so <strong>a winner always gets back at least what they bet</strong>.
        </p>
      </>
    ),
  },
  {
    title: "Your money stays yours",
    body: (
      <>
        <ul>
          <li>No company holds your IMD. The rules live in a public contract on Robinhood Chain.</li>
          <li>Nobody can pause markets, move funds or change a market after it opens.</li>
          <li>Anyone can trigger settlement. Winners claim their own payout.</li>
        </ul>
        <p className="text-mute">
          Know the risks: you can lose what you bet, the oracle can be wrong, and a question that is too vague ends in a
          refund. Betting closes before the answer is known; pick markets where that is clear.
        </p>
      </>
    ),
  },
  {
    title: "What comes next",
    body: (
      <>
        <ul>
          <li>
            <strong>Seeded markets</strong>, so new markets open with odds already on both sides.
          </li>
          <li>
            <strong>Rewards for early bets</strong>, so the people who set the odds first earn more.
          </li>
          <li>
            <strong>Selling before the end</strong>, so you can take profit or cut a loss.
          </li>
        </ul>
        <p>
          Conditionals turns &ldquo;what if&rdquo; into a price. Try it at{" "}
          <Link href="/" className="text-ink underline decoration-line-2 underline-offset-4">
            conditionals-bay.vercel.app
          </Link>
          .
        </p>
      </>
    ),
  },
];

export default function Docs() {
  const total = String(PAGES.length).padStart(2, "0");
  return (
    <>
      <header className="fixed inset-x-0 top-0 z-40 border-b border-line bg-bg/70 backdrop-blur-xl">
        <div className="mx-auto flex h-16 max-w-3xl items-center gap-6 px-4 sm:px-6">
          <Link href="/" className="flex items-center gap-2.5">
            <Logo />
            <span className="font-display text-[1.45rem] leading-none tracking-tight">Conditionals</span>
          </Link>
          <Link href="/" className="btn btn-primary ml-auto !py-2 text-sm">
            Open app
          </Link>
        </div>
      </header>

      <main className="mx-auto max-w-3xl px-4 pt-32 pb-24 sm:px-6">
        <p className="eyebrow">Whitepaper</p>
        <h1 className="mt-3 font-display text-5xl leading-[1.02] sm:text-7xl">
          Trade the world <em className="text-split-grad">where it happens.</em>
        </h1>
        <p className="mt-5 text-lg text-ink-2">Conditionals, explained in plain words. Eleven short pages.</p>

        <div className="mt-14 space-y-6">
          {PAGES.map((p, i) => {
            const n = String(i + 1).padStart(2, "0");
            return (
              <section key={p.title} id={`p${i + 1}`} className="panel scroll-mt-24 p-7 sm:p-10">
                <div className="flex items-center justify-between">
                  <span className="flex items-center gap-2">
                    <Logo size={18} />
                    <span className="eyebrow">Conditionals</span>
                  </span>
                  <a href={`#p${i + 1}`} className="num text-sm text-dim hover:text-ink">
                    {n} / {total}
                  </a>
                </div>
                <h2 className="mt-8 font-display text-4xl leading-tight sm:text-5xl">{p.title}</h2>
                <div className="doc mt-5">{p.body}</div>
              </section>
            );
          })}
        </div>

        <div className="mt-14 flex flex-wrap gap-x-8 gap-y-3 text-sm text-ink-2">
          {ADDRESSES.conditionals && (
            <a href={`${LINKS.explorer}/address/${ADDRESSES.conditionals}`} target="_blank" rel="noreferrer" className="hover:text-ink">
              Contract
            </a>
          )}
          <a href={LINKS.github} target="_blank" rel="noreferrer" className="hover:text-ink">
            GitHub
          </a>
          <a href={LINKS.x} target="_blank" rel="noreferrer" className="hover:text-ink">
            X
          </a>
          <a href={LINKS.imd} target="_blank" rel="noreferrer" className="hover:text-ink">
            IMD
          </a>
        </div>
        <p className="mt-10 text-xs text-dim">Not financial advice. Markets can be lost. The oracle can be wrong.</p>
      </main>
    </>
  );
}
