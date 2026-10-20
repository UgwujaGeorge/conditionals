import { fmtPct } from "@/lib/format";
import { worldPot, yesChance } from "@/lib/market";
import type { MarketView } from "@/lib/types";

/** The brand mark: one line that splits in two. */
export function Logo({ size = 26 }: { size?: number | string }) {
  return (
    <svg width={size} height={size} viewBox="0 0 32 32" fill="none" aria-hidden>
      <defs>
        <linearGradient id="lg-sun" x1="14" y1="16" x2="30" y2="5">
          <stop stopColor="#FFB547" />
          <stop offset="1" stopColor="#FF6A3D" />
        </linearGradient>
        <linearGradient id="lg-moon" x1="14" y1="16" x2="30" y2="27">
          <stop stopColor="#7DE3FF" />
          <stop offset="1" stopColor="#8B6CFF" />
        </linearGradient>
      </defs>
      <path d="M2 16h11" stroke="#F3EFE7" strokeWidth="2.4" strokeLinecap="round" />
      <path d="M13 16c5 0 6-10 16-10" stroke="url(#lg-sun)" strokeWidth="2.4" strokeLinecap="round" />
      <path d="M13 16c5 0 6 10 16 10" stroke="url(#lg-moon)" strokeWidth="2.4" strokeLinecap="round" />
      <circle cx="13" cy="16" r="2.6" fill="#FFF8EE" />
    </svg>
  );
}

/** A market as a fork: branch thickness follows each world's stakes, labels show YES in each world. */
export function ForkGlyph({ m, height = 120, settledWorld }: { m: MarketView; height?: number; settledWorld?: 0 | 1 }) {
  const total = worldPot(m, 0) + worldPot(m, 1);
  const share = (w: 0 | 1) => (total === 0 ? 0.5 : worldPot(m, w) / total);
  const width = (w: 0 | 1) => 1.5 + share(w) * 6;
  const h = height;
  const fy = h / 2;
  const dim = (w: 0 | 1) => (settledWorld === undefined ? 1 : settledWorld === w ? 1 : 0.18);
  const id = `g${m.id}`;
  return (
    <svg viewBox={`0 0 300 ${h}`} className="w-full" style={{ height: h }} aria-hidden>
      <defs>
        <linearGradient id={`${id}-sun`} x1="0" y1="0" x2="1" y2="0">
          <stop offset="0" stopColor="#FFB547" stopOpacity="0.95" />
          <stop offset="1" stopColor="#FF6A3D" stopOpacity="0.55" />
        </linearGradient>
        <linearGradient id={`${id}-moon`} x1="0" y1="0" x2="1" y2="0">
          <stop offset="0" stopColor="#7DE3FF" stopOpacity="0.95" />
          <stop offset="1" stopColor="#8B6CFF" stopOpacity="0.55" />
        </linearGradient>
        <radialGradient id={`${id}-glow`}>
          <stop offset="0" stopColor="#FFF4E4" stopOpacity="0.6" />
          <stop offset="1" stopColor="#FFF4E4" stopOpacity="0" />
        </radialGradient>
      </defs>
      <path d={`M0 ${fy}H96`} stroke="#F3EFE7" strokeOpacity="0.35" strokeWidth="1.5" />
      <path
        d={`M96 ${fy}C150 ${fy} 150 ${fy - h * 0.34} 236 ${fy - h * 0.34}`}
        stroke={`url(#${id}-sun)`}
        strokeWidth={width(0)}
        strokeLinecap="round"
        fill="none"
        opacity={dim(0)}
      />
      <path
        d={`M96 ${fy}C150 ${fy} 150 ${fy + h * 0.34} 236 ${fy + h * 0.34}`}
        stroke={`url(#${id}-moon)`}
        strokeWidth={width(1)}
        strokeLinecap="round"
        fill="none"
        opacity={dim(1)}
      />
      <circle cx="96" cy={fy} r="18" fill={`url(#${id}-glow)`} />
      <circle cx="96" cy={fy} r="3" fill="#FFF8EE" />
      <g fontFamily="var(--font-mono)" fontSize="13" fontWeight="500">
        <text x="246" y={fy - h * 0.34 + 4.5} fill="#FFB547" opacity={dim(0)}>
          {fmtPct(yesChance(m, 0))}
        </text>
        <text x="246" y={fy + h * 0.34 + 4.5} fill="#7DE3FF" opacity={dim(1)}>
          {fmtPct(yesChance(m, 1))}
        </text>
      </g>
    </svg>
  );
}

export function FlameIcon({ className = "" }: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" className={className} fill="none" aria-hidden>
      <path
        d="M12 2.5c.6 3.2 4.8 5.3 4.8 10.2A4.8 4.8 0 0 1 12 17.5a4.8 4.8 0 0 1-4.8-4.8c0-2 1-3.3 2-4.4.3 1.6 1.2 2.6 2.3 2.6-1-3 .5-6.3.5-8.4Z"
        fill="currentColor"
        opacity="0.9"
      />
      <path d="M8 21.5h8" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" opacity="0.5" />
    </svg>
  );
}

export function OracleIcon({ className = "" }: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" className={className} fill="none" aria-hidden>
      <circle cx="12" cy="12" r="9" stroke="currentColor" strokeWidth="1.5" opacity="0.5" />
      <circle cx="12" cy="12" r="3.2" fill="currentColor" />
      {[0, 72, 144, 216, 288].map((a) => (
        <circle
          key={a}
          cx={12 + 9 * Math.cos((a * Math.PI) / 180)}
          cy={12 + 9 * Math.sin((a * Math.PI) / 180)}
          r="1.6"
          fill="currentColor"
        />
      ))}
    </svg>
  );
}

export function ArrowIcon({ className = "" }: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" className={className} fill="none" aria-hidden>
      <path d="M5 12h14m-5-6 6 6-6 6" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}
