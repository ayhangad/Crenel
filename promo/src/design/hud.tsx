// React ports of the instruments the prototype engine draws from data attributes
// (docs/design/crenel-prototype.html: drawSeg, drawGauge, drawRamp, drawRuler, the
// telltales, VU meters, ladder, chart recorder) plus the dot orb from CrenelShaders.metal.
// Everything is a pure function of the frame, so renders are deterministic.
import React from 'react';
import { clamp01, fire, hash, loops, noise, useF } from '../lib';

type Cls = { className?: string; style?: React.CSSProperties };

// ── Icons: the prototype's <symbol> sprite.
export const Icon: React.FC<{ id: string } & Cls> = ({ id, className = 'ico', style }) => (
  <svg className={className} style={style}><use href={`#${id}`} /></svg>
);

const SOLID = new Set(['calendar', 'queue', 'mic', 'micoff', 'speaker', 'video', 'tape', 'transcript', 'spark', 'keyboard',
  'accessibility', 'gauge', 'waveform', 'sliders', 'sun', 'archive', 'warning', 'bell', 'shield']);

/** Telltale: an icon that lights. st = g | a | r | w | off. */
export const Telltale: React.FC<{ name: string; st?: string; paren?: boolean; brightness?: number } & Cls> = ({ name, st = 'off', paren, brightness, className = '', style }) => {
  const lit = st !== 'off';
  const glyph = lit && SOLID.has(name) ? `f-${name}` : `i-${name}`;
  return (
    <span className={`tt ${st}${paren ? ' paren' : ''} ${className}`} style={{ ...style, filter: brightness ? `brightness(${brightness})` : undefined }}>
      {paren && <svg className="p" viewBox="0 0 24 16"><use href="#i-paren" /></svg>}
      <svg className="ico" viewBox="0 0 16 16"><use href={`#${glyph}`} /></svg>
    </span>
  );
};

/** Lamp: `.lamp` (8×4 bar) or `.lamp.dot`. on = w | a | r | g | d | undefined (off). */
export const Lamp: React.FC<{ on?: string; dot?: boolean; opacity?: number; brightness?: number } & Cls> = ({ on, dot, opacity, brightness, className = '', style }) => (
  <span className={`lamp${dot ? ' dot' : ''}${on ? ` on-${on}` : ''} ${className}`}
    style={{ ...style, opacity, filter: brightness !== undefined && brightness !== 1 ? `brightness(${brightness})` : undefined }} />
);

export const FireLamp: React.FC<{ on: string; at: number; dot?: boolean } & Cls> = ({ on, at, dot, className, style }) => {
  const f = useF();
  return <Lamp on={f >= at ? on : undefined} dot={dot} brightness={fire(f, at)} className={className} style={style} />;
};

// ── Segment numerals (drawSeg).
const SEGS = (() => {
  const g = 0.55;
  const H = (x1: number, x2: number, y: number) => `${x1},${y} ${x1 + 1},${y - 1} ${x2 - 1},${y - 1} ${x2},${y} ${x2 - 1},${y + 1} ${x1 + 1},${y + 1}`;
  const V = (x: number, y1: number, y2: number) => `${x},${y1} ${x + 1},${y1 + 1} ${x + 1},${y2 - 1} ${x},${y2} ${x - 1},${y2 - 1} ${x - 1},${y1 + 1}`;
  return { a: H(1 + g, 9 - g, 1), b: V(9, 1 + g, 9 - g), c: V(9, 9 + g, 17 - g), d: H(1 + g, 9 - g, 17), e: V(1, 9 + g, 17 - g), f: V(1, 1 + g, 9 - g), g: H(1 + g, 9 - g, 9) } as Record<string, string>;
})();
const SEGMAP: Record<string, string> = { 0: 'abcdef', 1: 'bc', 2: 'abged', 3: 'abgcd', 4: 'fgbc', 5: 'afgcd', 6: 'afgedc', 7: 'abc', 8: 'abcdefg', 9: 'abcdfg', '-': 'g', ' ': '' };

export const Seg: React.FC<{ text: string; h?: number; cells?: number } & Cls> = ({ text, h = 14, cells = 0, className = '', style }) => {
  if (cells && text.length < cells) text = ' '.repeat(cells - text.length) + text;
  let x = 0;
  const parts: React.ReactNode[] = [];
  [...text].forEach((ch, ci) => {
    if (ch === ':' || ch === '.') {
      const dots = ch === ':' ? [5.5, 12.5] : [16.5];
      dots.forEach((y, k) => parts.push(<rect key={`d${ci}${k}`} x={x + 1} y={y - 1} width={2} height={2} rx={0.4} />));
      x += 5;
      return;
    }
    const on = SEGMAP[ch] ?? '';
    for (const k in SEGS) parts.push(<polygon key={`${ci}${k}`} points={SEGS[k]} transform={`translate(${x} 0)`} className={on.includes(k) ? 'on' : 'g'} />);
    x += 13;
  });
  const w = x - 3 + 2.6;
  return (
    <span className={`segd ${className}`} style={style}>
      <svg viewBox={`0 0 ${w} 18`} height={h} width={+((w / 18) * h).toFixed(1)} fill="currentColor">
        <g transform="translate(2.2 0) skewX(-7)">{parts}</g>
      </svg>
    </span>
  );
};

// ── Sweep gauge (drawGauge), with the ignition curve applied by the caller.
const ZC: Record<string, string> = { a: '#ffad33', r: '#ff5a47' };
export const Gauge: React.FC<{ v: number; id: string; size?: number; ticks?: number; major?: number; zones?: string } & Cls> = ({ v, id, size = 104, ticks: n = 60, major: maj = 15, zones: zs = '', className = '', style }) => {
  const sweep = 270, c = size / 2, r = c - 1.5;
  const lit = Math.round(v * n), ang = (i: number) => ((-sweep / 2 + (sweep * i) / (n - 1)) * Math.PI) / 180;
  const zones = zs.split('|').filter(Boolean).map((z) => { const [rg, k] = z.split(':'); const [a, b] = rg.split('-').map(Number); return { a, b, c: ZC[k] }; });
  const zoneOf = (i: number) => zones.reduce<null | { a: number; b: number; c: string }>((m, z) => (i >= z.a && i < z.b ? z : m), null);
  const ghost: React.ReactNode[] = [], on: React.ReactNode[] = [], dots: React.ReactNode[] = [];
  let head: React.ReactNode = null;
  for (let i = 0; i < n; i++) {
    const a = ang(i), major = maj && i % maj === 0, isHead = i === lit - 1 && lit < n;
    const len = (major ? size * 0.085 : size * 0.05) + (isHead ? 1.2 : 0);
    const x1 = c + Math.sin(a) * (r - len), y1 = c - Math.cos(a) * (r - len), x2 = c + Math.sin(a) * r, y2 = c - Math.cos(a) * r;
    const z = zoneOf(i), tint = z ? { stroke: z.c } : undefined;
    const tail = i - lit, tailOp = [0.42, 0.27, 0.17][tail];
    const props = { x1, y1, x2, y2, strokeWidth: major || isHead ? 1.7 : 1.25, style: tint };
    if (isHead) head = <line key={i} {...props} className="head" />;
    else if (i < lit) on.push(<line key={i} {...props} />);
    else if (lit > 0 && tailOp) ghost.push(<line key={i} {...props} opacity={tailOp} />);
    else ghost.push(<line key={i} {...props} {...(z ? { opacity: 0.26 } : { className: 'g' })} />);
    if (major && size >= 96) {
      const rd = r - size * 0.085 - size * 0.055, x = c + Math.sin(a) * rd, y = c - Math.cos(a) * rd;
      dots.push(<circle key={`c${i}`} cx={x} cy={y} r={size >= 140 ? 1.1 : 0.85} stroke="none" fill="currentColor" opacity={i < lit ? 0.9 : 0.22} />);
    }
  }
  const arc = (i0: number, i1: number, rr: number) => {
    const a0 = ang(i0), a1 = ang(i1);
    return `M${c + Math.sin(a0) * rr} ${c - Math.cos(a0) * rr} A${rr} ${rr} 0 ${a1 - a0 > Math.PI ? 1 : 0} 1 ${c + Math.sin(a1) * rr} ${c - Math.cos(a1) * rr}`;
  };
  return (
    <div className={`gauge ${className}`} style={style}>
      <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} stroke="currentColor" strokeLinecap="round">
        <defs><filter id={id} x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation={(size * 0.045).toFixed(1)} /></filter></defs>
        {lit > 1 && <path className="halo" d={arc(0, lit - 1, r - size * 0.04)} fill="none" strokeWidth={size * 0.1} filter={`url(#${id})`} />}
        {zones.map((z, k) => <path key={k} d={arc(z.a, Math.max(z.a, z.b - 1), r - size * 0.085 - size * 0.03)} fill="none" stroke={z.c} strokeWidth={1.5} strokeLinecap="butt" opacity={0.55} />)}
        {dots}
        <g>{ghost}</g>
        <g className="lit">{on}</g>
        {head}
      </svg>
    </div>
  );
};

/** Ignition: sweep to full (.42 s) and settle to the value (.52 s), ease-out cubic. */
export const ignite = (f: number, at: number, target: number) => {
  const t = (f - at) / 30, up = 0.42, down = 0.52, eo = (x: number) => 1 - Math.pow(1 - clamp01(x), 3);
  if (t < 0) return 0;
  return t < up ? eo(t / up) : t < up + down ? 1 - (1 - target) * eo((t - up) / down) : target;
};

// ── Day ruler (drawRuler).
export const Ruler: React.FC<{ span: [number, number]; now: number; events: string } & Cls> = ({ span: [a, b], now, events, className = '' }) => {
  const pct = (t: number) => ((t - a) / (b - a)) * 100;
  const out: React.ReactNode[] = [];
  events.split('|').filter(Boolean).forEach((e, k) => {
    const [rng, kind = ''] = e.split(':'); const [s, fi] = rng.split('-').map(Number);
    out.push(<i key={`e${k}`} className={`ev ${kind}${fi <= now ? ' past' : ''}`} style={{ left: `${pct(s)}%`, width: `calc(${pct(fi) - pct(s)}% - 2px)` }} />);
  });
  for (let t = a; t <= b + 1e-6; t += 0.5) {
    const M = Number.isInteger(t);
    out.push(<i key={`t${t}`} className={`tk ${M ? 'M' : ''} ${t < now ? 'past' : ''}`} style={{ left: `${pct(t)}%` }} />);
    if (M && t % 2 === 0 && t > a && t < b) out.push(<span key={`l${t}`} className="lb" style={{ left: `${pct(t)}%` }}>{String(t).padStart(2, '0')}</span>);
  }
  out.push(<i key="pm" className="past-mask" style={{ width: `${pct(now)}%` }} />);
  out.push(<i key="now" className="now" style={{ left: `${pct(now)}%` }} />);
  return <div className={`ruler ${className}`}>{out}</div>;
};

// ── Ramp (drawRamp): the band thickens as it rises; past the plan it's a red zone.
export const Ramp: React.FC<{ sec: number; plan: number; max: number; w: number }> = ({ sec, plan, max, w: W }) => {
  const H = 11, x = (t: number) => Math.min(W, (t / max) * W), y = (px: number) => H - 1.5 - (px / W) * (H - 3.5), xp = x(plan), xv = x(sec);
  const band = (x0: number, x1: number) => `M${x0} ${H} L${x0} ${y(x0)} L${x1} ${y(x1)} L${x1} ${H}Z`;
  const ticks: React.ReactNode[] = [];
  for (let t = 0; t <= max + 1; t += 300) { const M = t % 900 === 0; ticks.push(<rect key={t} x={x(t) - 0.5} y={H + 2} width={1} height={M ? 4 : 2} fill={t > plan ? '#ff5a47' : M ? '#76736e' : '#4c4a47'} />); }
  return (
    <div className="ramp">
      <svg width={W} height={H + 6}>
        <path d={band(0, W)} fill="rgba(255,255,255,.07)" />
        <path d={band(xp, W)} fill="rgba(255,90,71,.22)" />
        <path className="lit" d={band(0, Math.min(xv, xp))} fill="#f3f1ec" />
        <rect x={xp} y={H + 1} width={W - xp} height={1} fill="#ff5a47" opacity={0.8} />
        {ticks}
      </svg>
    </div>
  );
};

// ── Meters.
/** Ladder: six columns of four cells, the shape of a voice. Drawn as the app's dot matrix. */
export const Ladder: React.FC<{ quiet?: boolean; level?: number; seed?: number } & Cls> = ({ quiet, level = 1, seed = 1, className = '' }) => {
  const f = useF(), step = Math.floor(f / 3.3);
  const shape = [0.5, 0.8, 1, 0.9, 0.7, 0.45];
  return (
    <span className={`inline-flex items-end ${className}`} style={{ gap: 2.5, height: 14 }}>
      {shape.map((s, i) => {
        const lv = quiet ? 0.15 : s * (0.3 + hash(step, i + seed * 7) * 0.7) * level;
        const on = Math.round(lv * 4);
        return (
          <b key={i} className="flex flex-col-reverse" style={{ gap: 1.6 }}>
            {[0, 1, 2, 3].map((j) => (
              <i key={j} className="block" style={{ width: 3, height: 2.2, borderRadius: 1.1, background: j < on ? '#f3f1ec' : 'rgba(255,255,255,.1)', boxShadow: j < on ? '0 0 4px rgba(243,241,236,.5)' : undefined }} />
            ))}
          </b>
        );
      })}
    </span>
  );
};

/** VU meter: 30 cells, the last 14% red, a peak that holds .7 s and falls. */
export const Vu: React.FC<{ seed: number; n?: number; gain?: number }> = ({ seed, n = 30, gain = 1 }) => {
  const f = useF();
  const lv = (k: number) => clamp01((0.12 + 0.62 * Math.pow(noise(k / 3.2, seed), 1.25) + 0.3 * hash(Math.floor(k / 2), seed + 3) * (noise(k / 9, seed + 5) > 0.55 ? 1 : 0.3)) * gain);
  const lit = Math.round(lv(f) * n);
  let pk = lit;
  for (let k = 1; k <= 30; k++) { const l = Math.round(lv(f - k) * n) - Math.max(0, Math.floor((k - 21) / 2)); pk = Math.max(pk, l); }
  const red = n - Math.round(n * 0.14);
  return (
    <div className="vu">
      {Array.from({ length: n }, (_, i) => <i key={i} className={`${i >= red ? 'red' : ''} ${i < lit ? 'on' : ''} ${i === pk - 1 && i >= lit ? 'pk' : ''}`} />)}
    </div>
  );
};

/** Chart recorder: the last two minutes of sound, scrolling to the left. */
export const Chart: React.FC<{ at: number }> = ({ at }) => {
  const f = useF(), t = (f - at) / 3.3, n = Math.floor(t), sub = t - n;
  const h = (k: number) => (hash(k, 9) < 0.12 ? 1 + hash(k, 2) * 3 : 4 + Math.pow(hash(k, 4), 1.4) * 28);
  const bars = Array.from({ length: 130 }, (_, i) => n - 129 + i);
  return (
    <div className="chart" style={{ justifyContent: 'flex-end' }}>
      <div className="flex items-center" style={{ gap: 2, transform: `translateX(${(1 - sub) * 4}px)` }}>
        {bars.map((k, i) => <i key={k} className="block flex-none rounded-full" style={{ width: 2, height: Math.max(1, h(k)), background: i === bars.length - 1 ? '#f3f1ec' : '#76736e' }} />)}
      </div>
    </div>
  );
};

/** Station cells. state per cell: done | cur | on | off. */
export const Cells: React.FC<{ states: string[]; wide?: boolean } & Cls> = ({ states, className = '', style }) => {
  const f = useF();
  return (
    <span className={`cells ${className}`} style={style}>
      {states.map((s, i) => <i key={i} className={s === 'off' ? '' : s} style={s === 'cur' ? { opacity: loops.blink(f) } : undefined} />)}
    </span>
  );
};

// ── The mark: six lamps in a crenel.
const MARK = [[0.7, 59, 0, 118, 119], [0.76, 0, 119, 118, 118], [0.5, 118, 178, 118, 118], [0.65, 236, 178, 118, 118], [0.56, 295, 0, 118, 119], [1, 354, 119, 118, 118]];
export const Mark: React.FC<{ width: number; glow?: number; lit?: number[] } & Cls> = ({ width, glow = 2.5, lit, className = '', style }) => (
  <svg viewBox="0 0 472 296" width={width} height={(width * 296) / 472} className={className}
    style={{ color: '#14f0d4', filter: `drop-shadow(0 0 ${glow}px rgba(20,240,212,.6))`, overflow: 'visible', ...style }}>
    <g fill="currentColor">
      {MARK.map(([o, x, y, w, h], i) => <rect key={i} x={x} y={y} width={w} height={h} opacity={o * (lit ? lit[i] : 1)} />)}
    </g>
  </svg>
);

// ── Orb: the dictation orb (crenelDotOrb), drawn as dots on a turning sphere.
export const Orb: React.FC<{ size: number; level: number; at: number }> = ({ size, level, at }) => {
  const f = useF(), time = (f - at) / 30;
  const R = (size / 2) * 0.84 * (1 + level * 0.06), c = size / 2, rows = 12, tilt = 0.32, a = time * 0.35;
  const dots: React.ReactNode[] = [];
  for (let row = 0; row < rows; row++) {
    const lat = ((row + 0.5) / rows - 0.5) * Math.PI;
    const cols = Math.max(3, Math.floor(rows * 2 * Math.cos(lat)));
    for (let col = 0; col < cols; col++) {
      const lon = ((col + 0.5) / cols - 0.5) * 2 * Math.PI;
      // Cell in sphere space, then back into view space (inverse tilt, inverse spin).
      const qx = Math.cos(lat) * Math.sin(lon), qy = Math.sin(lat), qz = Math.cos(lat) * Math.cos(lon);
      const ty = qy * Math.cos(-tilt) - qz * Math.sin(-tilt), tz = qy * Math.sin(-tilt) + qz * Math.cos(-tilt);
      const px = qx * Math.cos(-a) + tz * Math.sin(-a), pz = -qx * Math.sin(-a) + tz * Math.cos(-a), py = ty;
      if (pz <= 0.02) continue;
      const pulse = 0.5 + 0.5 * Math.sin(time * 2.2 + hash(row, col) * 6.283);
      const dr = (0.55 + 0.25 * pulse * level + level * 0.35) * (Math.PI / rows) * 0.42 * R * 0.78;
      const facing = Math.min(1, pz / 0.6);
      const tmix = clamp01((py + 0.55) / 1.2);
      const col3 = [243 + (118 - 243) * tmix, 241 + (115 - 241) * tmix, 236 + (110 - 236) * tmix].map(Math.round);
      dots.push(<circle key={`${row}-${col}`} cx={c + px * R} cy={c + py * R} r={dr * (0.6 + 0.4 * facing)} fill={`rgb(${col3.join(',')})`} opacity={0.25 + 0.75 * facing} />);
    }
  }
  return (
    <svg width={size} height={size} style={{ overflow: 'visible' }}>
      <circle cx={c} cy={c} r={c} fill="rgba(255,255,255,.055)" />
      <circle cx={c} cy={c} r={R * 1.05} fill="rgba(200,198,192,.05)" style={{ filter: `blur(${2 + level * 3}px)` }} />
      {dots}
    </svg>
  );
};

/** A key on a strip or panel (`.btn-primary` / `.btn-secondary`), with a pressed state. */
export const Key: React.FC<{ kind?: 'primary' | 'secondary' | 'danger'; size?: 'sm' | ''; kbd?: string; pressed?: number; children: React.ReactNode } & Cls> = ({ kind = 'secondary', size = 'sm', kbd, pressed = 0, children, className = '', style }) => (
  <span className={`btn-${kind} ${size} ${className}`} style={{ ...style, transform: pressed ? `translateY(${0.5 * pressed}px) scale(${1 - 0.03 * pressed})` : undefined, filter: pressed ? `brightness(${1 - 0.12 * pressed})` : undefined }}>
    {children}
    {kbd && <span className="kbd">{kbd}</span>}
  </span>
);
