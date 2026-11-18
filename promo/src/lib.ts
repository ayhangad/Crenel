import { createContext, useContext } from 'react';
import { Easing, interpolate, spring } from 'remotion';

export const FPS = 30;

/** The frame every component reads. The poster freezes it; the video lets it run. */
export const FrameContext = createContext(0);
export const useF = () => useContext(FrameContext);

export const clamp01 = (x: number) => Math.max(0, Math.min(1, x));
export const lerp = (a: number, b: number, t: number) => a + (b - a) * t;

/** Hud.Motion curves (macos/Crenel/Features/Design/System/HudTokens.swift). */
export const EASE = {
  shape: Easing.bezier(0.3, 1.16, 0.4, 1),
  enter: Easing.bezier(0.2, 0.8, 0.2, 1),
  tabLamp: Easing.bezier(0.3, 1.25, 0.4, 1),
  rowSlide: Easing.bezier(0.3, 1.08, 0.4, 1),
  igniteOut: Easing.bezier(0.215, 0.61, 0.355, 1),
  camera: Easing.bezier(0.65, 0, 0.3, 1),
  out: Easing.bezier(0.2, 0.8, 0.2, 1),
};

/** 0…1 progress of frame f through [a, b] with an easing curve. */
export const prog = (f: number, a: number, b: number, ease: (t: number) => number = EASE.out) =>
  ease(clamp01((f - a) / Math.max(1, b - a)));

/** The notch's shape spring: a short overshoot, like the token curve (.3, 1.16, .4, 1). */
export const shapeSpring = (f: number) =>
  spring({ frame: f, fps: FPS, config: { damping: 18, stiffness: 190, mass: 1 } });

export const fade = (f: number, from: number, to: number, inDur = 6, outDur = 5, inDelay = 3) => {
  const a = interpolate(f, [from + inDelay, from + inDelay + inDur], [0, 1], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' });
  const b = interpolate(f, [to, to + outDur], [1, 0], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' });
  return Math.min(a, b);
};

/** Deterministic hash noise. */
export const hash = (a: number, b = 0) => {
  const s = Math.sin(a * 127.1 + b * 311.7) * 43758.5453;
  return s - Math.floor(s);
};

/** Smooth value noise 0…1. */
export const noise = (t: number, seed = 0) => {
  const i = Math.floor(t), fr = t - i, u = fr * fr * (3 - 2 * fr);
  return lerp(hash(i, seed), hash(i + 1, seed), u);
};

const sec = (f: number) => f / FPS;
/** The prototype's loops, driven by the frame instead of CSS animation. */
export const loops = {
  pulse: (f: number) => 0.65 + 0.35 * Math.cos((2 * Math.PI * sec(f)) / 1.4),
  breathe: (f: number) => 0.725 - 0.275 * Math.cos((2 * Math.PI * sec(f)) / 1.8),
  blink: (f: number) => ((sec(f) % 1.1) / 1.1 < 0.56 ? 1 : 0.18),
  caret: (f: number) => (sec(f) % 1 < 0.5 ? 1 : 0),
};

/** `lampon`: brightness .2 → 2.2 → 1 over .5 s, starting at frame `at`. */
export const fire = (f: number, at: number) => {
  const t = (f - at) / (0.5 * FPS);
  if (t < 0) return 0.2;
  if (t > 1) return 1;
  return t < 0.4 ? lerp(0.2, 2.2, t / 0.4) : lerp(2.2, 1, (t - 0.4) / 0.6);
};

export const fmt = (t: number) => {
  t = Math.max(0, Math.floor(t));
  const h = Math.floor(t / 3600), m = Math.floor((t % 3600) / 60), s = t % 60;
  return h ? `${h}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}` : `${m}:${String(s).padStart(2, '0')}`;
};
