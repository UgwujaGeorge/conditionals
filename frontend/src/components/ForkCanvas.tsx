"use client";

import { useEffect, useRef } from "react";

type Pt = { x: number; y: number };
type Particle = { seg: 0 | 1; t: number; v: number; branch: 0 | 1; r: number; lane: number };

const SUN: [number, number, number][] = [
  [255, 181, 71],
  [255, 106, 61],
];
const MOON: [number, number, number][] = [
  [125, 227, 255],
  [139, 108, 255],
];

function mix(a: [number, number, number], b: [number, number, number], t: number) {
  return a.map((v, i) => Math.round(v + (b[i] - v) * t)) as [number, number, number];
}

function bezier(p0: Pt, p1: Pt, p2: Pt, p3: Pt, t: number): Pt {
  const u = 1 - t;
  return {
    x: u * u * u * p0.x + 3 * u * u * t * p1.x + 3 * u * t * t * p2.x + t * t * t * p3.x,
    y: u * u * u * p0.y + 3 * u * u * t * p1.y + 3 * u * t * t * p2.y + t * t * t * p3.y,
  };
}

/**
 * One timeline comes in from the left and forks into two worlds: warm where the event happens, cool where it
 * doesn't. Particles flow along it; the pointer tilts how many take each branch.
 */
export function ForkCanvas({ bias = 0.5, className = "" }: { bias?: number; className?: string }) {
  const ref = useRef<HTMLCanvasElement>(null);
  const biasRef = useRef(bias);
  useEffect(() => {
    biasRef.current = bias;
  }, [bias]);

  useEffect(() => {
    const canvas = ref.current;
    if (!canvas) return;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

    let W = 0;
    let H = 0;
    let dpr = 1;
    let raf = 0;
    let pointer = 0.5;
    let pointerTarget = 0.5;
    const stars: { x: number; y: number; r: number; p: number }[] = [];
    const particles: Particle[] = [];

    const geometry = () => {
      // Wide screens: the fork sits right of the headline. Narrow: below the buttons.
      const narrow = W < 760;
      const fork: Pt = { x: W * (narrow ? 0.22 : 0.6), y: H * (narrow ? 0.84 : 0.56) };
      const spread = H * (narrow ? 0.09 : 0.34);
      const tilt = (pointer - 0.5) * H * 0.08;
      const endA: Pt = { x: W * 1.04, y: fork.y - spread + tilt };
      const endB: Pt = { x: W * 1.04, y: fork.y + spread * 0.9 + tilt };
      const ctrl = W * 0.2;
      return {
        // On wide screens the timeline emerges just right of the text instead of running under it.
        start: (narrow ? { x: -W * 0.04, y: fork.y + H * 0.04 } : { x: W * 0.47, y: fork.y + H * 0.02 }) as Pt,
        fork,
        a: [fork, { x: fork.x + ctrl, y: fork.y }, { x: fork.x + ctrl * 1.3, y: endA.y }, endA] as const,
        b: [fork, { x: fork.x + ctrl, y: fork.y }, { x: fork.x + ctrl * 1.3, y: endB.y }, endB] as const,
      };
    };

    const trunkAt = (g: ReturnType<typeof geometry>, t: number, lane: number): Pt => ({
      x: g.start.x + (g.fork.x - g.start.x) * t,
      y: g.start.y + (g.fork.y - g.start.y) * t + Math.sin(t * 9 + lane * 6) * 3 * (1 - t) + lane * 10 * (1 - t),
    });

    const branchAt = (g: ReturnType<typeof geometry>, branch: 0 | 1, t: number, lane: number): Pt => {
      const p = bezier(...(branch === 0 ? g.a : g.b), t);
      return { x: p.x, y: p.y + lane * 18 * t };
    };

    const spawn = (p?: Particle): Particle => {
      const np: Particle = p ?? ({} as Particle);
      np.seg = 0;
      np.t = Math.random() * (p ? 0.05 : 1);
      np.v = 0.0018 + Math.random() * 0.0032;
      np.branch = Math.random() < biasRef.current * 0.6 + pointer * 0.4 ? 1 : 0;
      np.r = 0.6 + Math.random() * 1.6;
      np.lane = (Math.random() - 0.5) * 2;
      return np;
    };

    const resize = () => {
      const rect = canvas.getBoundingClientRect();
      dpr = Math.min(window.devicePixelRatio || 1, 2);
      W = rect.width;
      H = rect.height;
      canvas.width = Math.floor(W * dpr);
      canvas.height = Math.floor(H * dpr);
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      stars.length = 0;
      const count = Math.floor((W * H) / 9000);
      for (let i = 0; i < count; i++) {
        stars.push({ x: Math.random() * W, y: Math.random() * H, r: Math.random() * 1.1, p: Math.random() * Math.PI * 2 });
      }
      particles.length = 0;
      const n = Math.floor(Math.min(320, W / 4));
      for (let i = 0; i < n; i++) particles.push(spawn());
      ctx.fillStyle = "#060608";
      ctx.fillRect(0, 0, W, H);
    };

    const strokePath = (pts: Pt[], color: string, width: number) => {
      ctx.beginPath();
      pts.forEach((p, i) => (i ? ctx.lineTo(p.x, p.y) : ctx.moveTo(p.x, p.y)));
      ctx.strokeStyle = color;
      ctx.lineWidth = width;
      ctx.stroke();
    };

    let time = 0;
    const frame = () => {
      time += 1;
      pointer += (pointerTarget - pointer) * 0.04;
      const g = geometry();

      // Fade the last frame to leave trails.
      ctx.globalCompositeOperation = "source-over";
      ctx.fillStyle = reduced ? "#060608" : "rgba(6,6,8,0.2)";
      ctx.fillRect(0, 0, W, H);

      // Stars.
      for (const s of stars) {
        const a = 0.25 + 0.35 * Math.sin(s.p + time * 0.01);
        ctx.fillStyle = `rgba(243,239,231,${a * 0.5})`;
        ctx.fillRect(s.x, s.y, s.r, s.r);
      }

      // Ghost timelines: faint alternatives fanning out from the fork.
      ctx.globalCompositeOperation = "lighter";
      for (let k = -3; k <= 3; k++) {
        if (k === 0) continue;
        const end: Pt = { x: W * 1.04, y: g.fork.y + k * H * 0.13 };
        const pts: Pt[] = [];
        for (let i = 0; i <= 40; i++) {
          pts.push(bezier(g.fork, { x: g.fork.x + W * 0.2, y: g.fork.y }, { x: g.fork.x + W * 0.28, y: end.y }, end, i / 40));
        }
        strokePath(pts, `rgba(243,239,231,${0.025 - Math.abs(k) * 0.004})`, 1);
      }

      // The trunk and the two worlds.
      const trunk: Pt[] = [];
      for (let i = 0; i <= 60; i++) trunk.push(trunkAt(g, i / 60, 0));
      const trunkGrad = ctx.createLinearGradient(g.start.x, 0, g.fork.x, 0);
      trunkGrad.addColorStop(0, "rgba(243,239,231,0)");
      trunkGrad.addColorStop(1, "rgba(243,239,231,0.22)");
      strokePath(trunk, trunkGrad as unknown as string, 1.4);
      for (const branch of [0, 1] as const) {
        const pts: Pt[] = [];
        for (let i = 0; i <= 80; i++) pts.push(branchAt(g, branch, i / 80, 0));
        const grad = ctx.createLinearGradient(g.fork.x, g.fork.y, W, branch === 0 ? g.a[3].y : g.b[3].y);
        const [c0, c1] = branch === 0 ? SUN : MOON;
        grad.addColorStop(0, `rgba(${c0.join(",")},0.35)`);
        grad.addColorStop(1, `rgba(${c1.join(",")},0.12)`);
        strokePath(pts, grad as unknown as string, 1.6);
      }

      // Particles.
      for (const p of particles) {
        if (!reduced) p.t += p.v * (p.seg === 0 ? 1.15 : 0.85);
        if (p.seg === 0 && p.t >= 1) {
          p.seg = 1;
          p.t = 0;
          p.branch = Math.random() < biasRef.current * 0.6 + pointer * 0.4 ? 1 : 0;
        } else if (p.seg === 1 && p.t >= 1) {
          spawn(p);
        }
        let pos: Pt;
        let rgb: [number, number, number];
        let alpha: number;
        if (p.seg === 0) {
          pos = trunkAt(g, p.t, p.lane);
          rgb = [243, 239, 231];
          alpha = Math.min(1, p.t * 2.5) * (0.35 + p.t * 0.5);
        } else {
          pos = branchAt(g, p.branch, p.t, p.lane);
          const [c0, c1] = p.branch === 0 ? SUN : MOON;
          rgb = mix(c0, c1, p.t);
          alpha = 0.9 * (1 - p.t * 0.6);
        }
        ctx.fillStyle = `rgba(${rgb.join(",")},${alpha})`;
        ctx.beginPath();
        ctx.arc(pos.x, pos.y, p.r, 0, Math.PI * 2);
        ctx.fill();
      }

      // The fork: a breathing point of light.
      const pulse = 0.75 + 0.25 * Math.sin(time * 0.04);
      const glow = ctx.createRadialGradient(g.fork.x, g.fork.y, 0, g.fork.x, g.fork.y, 140 * pulse);
      glow.addColorStop(0, "rgba(255,240,220,0.32)");
      glow.addColorStop(0.25, "rgba(255,181,71,0.08)");
      glow.addColorStop(0.6, "rgba(139,108,255,0.04)");
      glow.addColorStop(1, "rgba(0,0,0,0)");
      ctx.fillStyle = glow;
      ctx.fillRect(g.fork.x - 160, g.fork.y - 160, 320, 320);
      ctx.fillStyle = "rgba(255,248,238,0.95)";
      ctx.beginPath();
      ctx.arc(g.fork.x, g.fork.y, 2.6, 0, Math.PI * 2);
      ctx.fill();

      if (!reduced) raf = requestAnimationFrame(frame);
    };

    const onPointer = (e: PointerEvent) => {
      const rect = canvas.getBoundingClientRect();
      pointerTarget = Math.min(1, Math.max(0, (e.clientY - rect.top) / rect.height));
    };

    resize();
    frame();
    const ro = new ResizeObserver(resize);
    ro.observe(canvas);
    window.addEventListener("pointermove", onPointer, { passive: true });
    return () => {
      cancelAnimationFrame(raf);
      ro.disconnect();
      window.removeEventListener("pointermove", onPointer);
    };
  }, []);

  return <canvas ref={ref} className={`block h-full w-full ${className}`} aria-hidden />;
}
