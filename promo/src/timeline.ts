// The whole film on one clock (30 fps). Every beat reads its frames from here.
import { EASE, clamp01, lerp, prog, shapeSpring } from './lib';

export const DURATION = 1020;

export const T = {
  // 1 · the ears
  ears: 30,
  // 2 · hover opens Today
  hover1: 108,
  open1: 114,
  close1: 250,
  // 3 · dictation
  fnShow: 256,
  fnDown: 266,
  dict: 270,
  wordsFrom: 278,
  wordStep: 4,
  fnUp: 356,
  inserted: 376,
  // 4 · the call
  call: 452,
  clickRec: 508,
  rec: 514,
  hover2: 530,
  open2: 536,
  clickStop: 632,
  // 5 · processing
  proc: 638,
  transcribing: 654,
  summarizing: 670,
  ready: 690,
  // 6 · tasks
  hover3: 758,
  open3: 764,
  typeFrom: 790,
  typeStep: 2,
  enter: 846,
  // 7 · end
  end: 900,
  card: 906,
};

export const WORDS = 'Let’s move the design review to Thursday afternoon, and send Deniz the new onboarding copy before then'.split(' ');
export const wordAt = (i: number) => T.wordsFrom + i * T.wordStep;
/** "afternoon," pushes past one strip line: the live size takes over. */
export const LIVE1 = wordAt(7);
/** "send" starts the second line. */
export const LIVE2 = wordAt(9);
export const LINE1 = 9;

export const TASK_TEXT = 'Call mom tomorrow 3pm';
export const typedAt = (f: number) => TASK_TEXT.slice(0, Math.max(0, Math.min(TASK_TEXT.length, Math.floor((f - T.typeFrom) / T.typeStep) + 1)));
export const CHIP1 = T.typeFrom + ('Call mom tomorrow'.length - 1) * T.typeStep;
export const CHIP2 = T.typeFrom + (TASK_TEXT.length - 1) * T.typeStep;

// ── Notch shapes (HudTokens: Hud.Notch).
export type Shape = { w: number; h: number; rt: number; rb: number };
const compact = (w: number): Shape => ({ w, h: 32, rt: 6, rb: 10 });
const strip = (h = 80): Shape => ({ w: 440, h, rt: 9, rb: 18 });
const open = (h: number): Shape => ({ w: 560, h, rt: 14, rb: 24 });
const lean = (s: Shape): Shape => ({ ...s, w: s.w + 14, h: s.h + 4 });

export const H_TODAY = 494;
export const H_REC = 380;
export const H_TASKS = 438;
export const W_MEETING = 437;
export const W_REC = 340;
export const W_PROC = 416;

const SHAPES: [number, Shape][] = [
  [0, compact(186)],
  [T.ears, compact(W_MEETING)],
  [T.hover1, lean(compact(W_MEETING))],
  [T.open1, open(H_TODAY)],
  [T.close1, compact(W_MEETING)],
  [T.dict, strip()],
  [LIVE2, strip(94)],
  [T.fnUp, strip()],
  [T.call - 16, compact(186)],
  [T.call, strip()],
  [T.rec, compact(W_REC)],
  [T.hover2, lean(compact(W_REC))],
  [T.open2, open(H_REC)],
  [T.proc, compact(W_PROC)],
  [T.ready, strip()],
  [T.hover3, lean(strip())],
  [T.open3, open(H_TASKS)],
  [CHIP1 + 2, open(H_TASKS + 30)],
  [T.enter, open(H_TASKS + 38)],
  [T.end, compact(186)],
];

const mix = (a: Shape, b: Shape, t: number): Shape => ({ w: lerp(a.w, b.w, t), h: lerp(a.h, b.h, t), rt: lerp(a.rt, b.rt, t), rb: lerp(a.rb, b.rb, t) });

/** The shape at frame f: each change springs from wherever the last one had got to. */
export const shapeAt = (f: number): Shape => {
  let from = SHAPES[0][1], to = SHAPES[0][1], start = SHAPES[0][0];
  for (let i = 1; i < SHAPES.length && SHAPES[i][0] <= f; i++) {
    from = mix(from, to, shapeSpring(SHAPES[i][0] - start));
    to = SHAPES[i][1];
    start = SHAPES[i][0];
  }
  return mix(from, to, shapeSpring(f - start));
};

// ── Camera: scale about the top centre of the screen, where the notch hangs.
const CAM: [number, number, number][] = [
  // [start, end, scale reached at end]
  [0, 14, 1.22],
  [16, 72, 3.0],
  [T.open1 - 2, T.open1 + 30, 1.8],
  [T.close1, T.close1 + 30, 3.0],
  [T.open2 - 2, T.open2 + 28, 2.3],
  [T.proc, T.proc + 28, 3.0],
  [T.open3 - 2, T.open3 + 28, 1.82],
  [T.end, T.end + 46, 1.0],
];
export const camAt = (f: number) => {
  let s = CAM[0][2];
  for (const [a, b, to] of CAM) {
    if (f < a) break;
    s = lerp(s, to, prog(f, a, b, EASE.camera));
  }
  return s;
};

// ── Cursor path, in screen points (notch centre is x 960, top is y 0).
type P = [number, number, number, number]; // frame, x, y, opacity
const CURSOR: P[] = [
  [T.hover1 - 22, 1190, 320, 0],
  [T.hover1 - 14, 1150, 230, 1],
  [T.hover1, 990, 22, 1],
  [T.open1 + 34, 1090, 118, 1],
  [T.close1 - 24, 1110, 140, 1],
  [T.close1 - 6, 1200, 560, 0],
  [T.clickRec - 26, 1210, 230, 0],
  [T.clickRec - 18, 1180, 160, 1],
  [T.clickRec - 3, 1127, 54, 1],
  [T.clickRec + 8, 1127, 54, 1],
  [T.hover2, 1000, 20, 1],
  [T.open2 + 30, 1060, 160, 1],
  [T.clickStop - 26, 1080, 170, 1],
  [T.clickStop - 4, 1196, 122, 1],
  [T.clickStop + 8, 1196, 122, 1],
  [T.clickStop + 30, 1260, 420, 0],
  [T.hover3 - 24, 1210, 330, 0],
  [T.hover3 - 14, 1160, 220, 1],
  [T.hover3, 995, 30, 1],
  [T.open3 + 16, 1050, 120, 1],
  [T.open3 + 34, 1230, 340, 0],
];
export const cursorAt = (f: number) => {
  if (f <= CURSOR[0][0]) return { x: CURSOR[0][1], y: CURSOR[0][2], o: CURSOR[0][3] };
  for (let i = 1; i < CURSOR.length; i++) {
    const [fa, xa, ya, oa] = CURSOR[i - 1], [fb, xb, yb, ob] = CURSOR[i];
    if (f <= fb) {
      const t = EASE.camera(clamp01((f - fa) / (fb - fa)));
      return { x: lerp(xa, xb, t), y: lerp(ya, yb, t), o: lerp(oa, ob, t) };
    }
  }
  const l = CURSOR[CURSOR.length - 1];
  return { x: l[1], y: l[2], o: l[3] };
};
/** 0…1 press depth around a click frame. */
export const press = (f: number, at: number) => clamp01(1 - Math.abs(f - at) / 4);
