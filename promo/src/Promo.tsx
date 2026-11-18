import React from 'react';
import { AbsoluteFill, getInputProps, useCurrentFrame } from 'remotion';
import './styles/proto.css';
import { SPRITE } from './design/sprite';
import { Icon, Lamp, Mark } from './design/hud';
import { EASE, FrameContext, clamp01, fade, fire, lerp, prog, useF } from './lib';
import { DURATION, LIVE1, T, camAt, cursorAt, press, shapeAt } from './timeline';
import { DictInserted, DictListening, DictLive, DictWriting, Fuse, MeetingEars, ProcEars, PromptOffer, ReadyStrip, RecordingEars } from './notch/Closed';
import { RecordingPanel, TasksPanel, TodayPanel } from './notch/Panels';

// ── The Mac: a light wallpaper and the notch, nothing else.

/** `--props '{"flat":true}'`: a flat wallpaper for the GIF, where gradients cost colours and bytes. */
const FLAT = Boolean((getInputProps() as { flat?: boolean }).flat);

/** A light, smooth abstract wallpaper in the app's colours (teal, cyan, blue, sky, a touch of amber) that drifts slowly.
 *  The black notch reads against it; nothing in it competes for attention. */
const FIELDS = [
  // The app's own colours: teal (ok #34E6CB, mark #14F0D4), a blue beside it, a touch of amber (signal #FFAD33).
  { c: '#c8fbf2', x: 30, y: 18, w: 70, h: 42, r: -28, p: 0.0, o: 0.95 },  // pale teal glow
  { c: '#14f0d4', x: 16, y: 66, w: 46, h: 70, r: -20, p: 1.2, o: 0.9 },   // mark teal mass
  { c: '#22c7d8', x: 32, y: 60, w: 34, h: 90, r: -38, p: 2.1, o: 0.85 },  // cyan band
  { c: '#2f8cf0', x: 46, y: 52, w: 22, h: 95, r: -42, p: 3.0, o: 0.8 },   // blue band
  { c: '#5b6cf2', x: 58, y: 52, w: 24, h: 95, r: -46, p: 3.9, o: 0.55 },  // indigo hint
  { c: '#a9d8f7', x: 72, y: 60, w: 40, h: 90, r: -48, p: 4.8, o: 0.75 },  // sky
  { c: '#ffad33', x: 8, y: 98, w: 16, h: 18, r: -20, p: 5.5, o: 0.45 },   // amber, just a touch
];

const LivingWallpaper: React.FC = () => {
  const f = useCurrentFrame();
  const t = f / 30;
  return (
    <div className="absolute inset-0 overflow-hidden" style={{ background: '#fbf8fb' }}>
      {FIELDS.map((b, i) => {
        const x = b.x + Math.sin(t * 0.14 + b.p) * 2.4;
        const y = b.y + Math.cos(t * 0.11 + b.p) * 2.0;
        const r = b.r + Math.sin(t * 0.09 + b.p) * 3;
        return (
          <div key={i} className="absolute" style={{
            left: `${x}%`, top: `${y}%`, width: `${b.w}vw`, height: `${b.h}vw`,
            transform: `translate(-50%, -50%) rotate(${r}deg)`, borderRadius: '50%',
            background: `radial-gradient(closest-side, ${b.c} 0%, ${b.c}00 100%)`,
            filter: 'blur(48px)', opacity: b.o,
          }} />
        );
      })}
      {/* White falls in from the far left and the right, like the reference. */}
      <div className="absolute inset-0" style={{ background: 'radial-gradient(ellipse 22% 70% at -4% 45%, #fff 30%, #fff0 100%), radial-gradient(ellipse 45% 75% at 100% 80%, #fff 20%, #fff0 100%)' }} />
      {/* Fine grain keeps the gradients from banding. */}
      <svg className="absolute inset-0 w-full h-full" style={{ opacity: 0.09, mixBlendMode: 'soft-light' }}>
        <filter id="grain"><feTurbulence type="fractalNoise" baseFrequency="0.85" numOctaves="2" seed={f % 4} /></filter>
        <rect width="100%" height="100%" filter="url(#grain)" />
      </svg>
    </div>
  );
};

const Desktop: React.FC = () => FLAT ? (
  <>
    <div className="absolute inset-0" style={{ background: 'linear-gradient(115deg, #7fe9dc 0%, #8ccff2 40%, #cfe3fb 70%, #f7f9fc 100%)' }} />
  </>
) : (
  <>
    <LivingWallpaper />
  </>
);

// ── The notch: one black shape that springs between sizes; states cross-fade inside it.
const Layer: React.FC<{ from: number; to: number; children: React.ReactNode; inDelay?: number }> = ({ from, to, children, inDelay = 4 }) => {
  const f = useF();
  if (f < from || f > to + 6) return null;
  const o = fade(f, from, to, 6, 4, inDelay);
  return <div className="absolute top-0 left-1/2" style={{ transform: 'translateX(-50%)', opacity: o }}>{children}</div>;
};

const Notch: React.FC = () => {
  const f = useF(), s = shapeAt(f);
  const openness = clamp01((s.h - 40) / 160);
  const shoulder = (side: 'l' | 'r') => (
    <div className="absolute top-0" style={{
      [side === 'l' ? 'left' : 'right']: -s.rt, width: s.rt, height: s.rt,
      background: `radial-gradient(circle at ${side === 'l' ? '0' : '100%'} 100%, transparent ${s.rt - 0.5}px, #000 ${s.rt}px)`,
    }} />
  );
  return (
    <div className="absolute top-0" style={{ left: 960, transform: 'translateX(-50%)' }}>
      {shoulder('l')}{shoulder('r')}
      <div className="relative overflow-hidden" style={{
        width: s.w, height: s.h, background: '#000', borderRadius: `0 0 ${s.rb}px ${s.rb}px`,
        boxShadow: `0 ${20 * openness}px ${60 * openness}px rgba(0,0,0,${0.55 * openness})`,
      }}>
        {/* The camera, a hair lighter than the black around it. */}
        <span className="absolute rounded-full" style={{ left: '50%', top: 11, width: 9, height: 9, transform: 'translateX(-50%)', background: 'radial-gradient(circle at 38% 34%, #151a26 0%, #07090d 50%, #020203 80%)', boxShadow: '0 0 0 1.5px #050506' }} />

        <Layer from={T.ears} to={T.hover1 + 4}><MeetingEars /></Layer>
        <Layer from={T.open1} to={T.close1} inDelay={4}><TodayPanel /></Layer>
        <Layer from={T.close1} to={T.dict}><MeetingEars /></Layer>
        <Layer from={T.dict} to={LIVE1}><DictListening /></Layer>
        <Layer from={LIVE1} to={T.fnUp} inDelay={1}><DictLive /></Layer>
        <Layer from={T.fnUp} to={T.inserted}><DictWriting /></Layer>
        <Layer from={T.inserted} to={T.call - 16}><DictInserted /></Layer>
        <Layer from={T.call} to={T.rec}><PromptOffer /></Layer>
        <Layer from={T.rec} to={T.hover2 + 4}><RecordingEars /></Layer>
        <Layer from={T.open2} to={T.proc} inDelay={4}><RecordingPanel /></Layer>
        <Layer from={T.proc} to={T.ready}><ProcEars /></Layer>
        <Layer from={T.ready} to={T.hover3 + 4}><ReadyStrip /></Layer>
        <Layer from={T.open3} to={T.end} inDelay={4}><TasksPanel /></Layer>

        <Fuse w={s.w} rb={s.rb} v={lerp(0.8, 0.76, prog(f, T.ears, T.hover1))} opacity={Math.max(fade(f, T.ears, T.hover1, 10, 4, 10), fade(f, T.close1, T.dict, 10, 4, 10))} />
      </div>
    </div>
  );
};

/** The macOS arrow pointer. */
const Cursor: React.FC = () => {
  const f = useF(), c = cursorAt(f);
  const p = Math.max(press(f, T.clickRec), press(f, T.clickStop));
  if (c.o <= 0.01) return null;
  return (
    <svg className="absolute" width="22" height="32" viewBox="0 0 22 32" style={{ left: c.x - 4, top: c.y - 3, opacity: c.o, transform: `scale(${1 - 0.12 * p})`, transformOrigin: '4px 3px', filter: 'drop-shadow(0 1.5px 2.5px rgba(0,0,0,.45))' }}>
      <path d="M4 3 L4 25 L9.2 20.2 L12.6 28.2 L16 26.7 L12.7 18.9 L19.6 18.9 Z" fill="#000" stroke="#fff" strokeWidth="1.6" strokeLinejoin="round" />
    </svg>
  );
};

// ── Overlays in frame space: captions, the fn key, the end card.
const CAPTIONS: [number, number, string][] = [
  [40, 104, 'Your next meeting, counting down.'],
  [T.open1 + 14, T.close1 - 6, 'Hover for your whole day.'],
  [T.dict + 4, T.fnUp - 2, 'Hold fn and talk.'],
  [T.inserted - 4, T.call - 16, 'Transcribed on your Mac.'],
  [T.call + 10, T.clickStop - 4, 'Record Zoom and Meet calls.'],
  [T.proc + 12, T.hover3 - 2, 'Notes, decisions, action items.'],
  [T.open3 + 14, T.end - 4, 'One line. Saved to Reminders.'],
];

const Caption: React.FC<{ from: number; to: number; text: string }> = ({ from, to, text }) => {
  const f = useF();
  if (f < from || f > to + 10) return null;
  const out = prog(f, to, to + 9, EASE.out);
  return (
    <div className="absolute inset-x-0 flex justify-center" style={{ bottom: 66, opacity: 1 - out, transform: `translateY(${-8 * out}px)` }}>
      <div className="flex gap-[0.26em]" style={{ fontSize: 46, fontWeight: 600, letterSpacing: '-0.014em', lineHeight: 1.1, color: '#111014' }}>
        {text.split(' ').map((w, i) => {
          const p = prog(f, from + i * 2.5, from + i * 2.5 + 12, EASE.enter);
          return <span key={i} style={{ opacity: p, transform: `translateY(${(1 - p) * 14}px)`, filter: `blur(${(1 - p) * 6}px)` }}>{w}</span>;
        })}
      </div>
    </div>
  );
};

/** HudBigKeycap("fn", glyph: .globe, lamp: .teal), held while you talk. */
const FnKey: React.FC = () => {
  const f = useF();
  const show = fade(f, T.fnShow, T.fnUp + 6, 8, 8, 0);
  if (show <= 0) return null;
  const down = Math.min(prog(f, T.fnDown - 2, T.fnDown + 2), 1 - prog(f, T.fnUp, T.fnUp + 4));
  const held = f >= T.fnDown && f < T.fnUp;
  return (
    <div className="absolute" style={{ left: 960, top: 600, transform: `translate(-50%, -50%) scale(${2.6 * (0.92 + 0.08 * show)})`, opacity: show }}>
      <div className="keycap" style={{ transform: `translateY(${3 * down}px)`, boxShadow: `inset 0 1px 0 rgba(255,255,255,.1), inset 0 0 0 1px rgba(255,255,255,.06), 0 ${4 - 3 * down}px 0 #050505, 0 ${5 - 3 * down}px ${12 - 6 * down}px rgba(0,0,0,.6)` }}>
        <Lamp on={held ? 'g' : undefined} brightness={held ? fire(f, T.fnDown) : 1} className="self-end" />
        <span className="flex items-center justify-between"><span className="text-[13px] font-medium" style={{ color: held ? '#f3f1ec' : '#aaa7a1' }}>fn</span><Icon id="i-globe" className="ico-s text-ink-3" /></span>
      </div>
    </div>
  );
};

const EndCard: React.FC = () => {
  const f = useF(), at = T.card;
  if (f < at - 20) return null;
  const step = (i: number, d = 14) => prog(f, at + i, at + i + d, EASE.enter);
  const lit = [0, 1, 2, 3, 4, 5].map((i) => clamp01(fire(f, at + 2 + [2, 0, 4, 6, 8, 10][i]) / 1.0) * (f >= at + 2 + [2, 0, 4, 6, 8, 10][i] ? 1 : 0));
  const rise = (i: number) => ({ opacity: step(i), transform: `translateY(${(1 - step(i)) * 16}px)` });
  return (
    <AbsoluteFill>
      <AbsoluteFill className="flex flex-col items-center justify-center" style={{ paddingTop: 30 }}>
        <div className="flex items-center" style={{ gap: 30 }}>
          <Mark width={132} glow={10} lit={lit.map((v) => Math.min(1.3, v))} />
          <span style={{ fontSize: 112, fontWeight: 600, letterSpacing: '-0.03em', lineHeight: 1, ...rise(12), color: '#0b0b0a' }}>Crenel</span>
        </div>
        <div style={{ marginTop: 34, fontSize: 44, fontWeight: 500, letterSpacing: '-0.014em', color: '#0b0b0a', ...rise(22) }}>Your Mac’s notch, at work.</div>
        <div className="flex items-center" style={{ marginTop: 30, gap: 14, fontSize: 26, fontWeight: 500, color: '#2e2d2b', ...rise(30) }}>
          <Lamp on="g" style={{ transform: 'scale(2)', marginRight: 6 }} />Open source · on-device
        </div>
        <div style={{ marginTop: 16, fontSize: 26, fontWeight: 400, color: '#4c4a47', ...rise(36) }}>github.com/ayhangad/Crenel</div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

export const Scene: React.FC<{ still?: boolean }> = ({ still }) => {
  const f = useF(), s = camAt(f);
  return (
    <AbsoluteFill className="promo" style={{ background: '#000' }}>
      <div dangerouslySetInnerHTML={{ __html: SPRITE }} />
      <div className="absolute left-0 top-0 overflow-hidden" style={{ width: 1920, height: 1080, transformOrigin: '960px 0px', transform: `scale(${s})` }}>
        <Desktop />
        <Notch />
        {!still && <Cursor />}
      </div>
      <FnKey />
      {!still && CAPTIONS.map(([a, b, t]) => <Caption key={t} from={a} to={b} text={t} />)}
      <EndCard />
    </AbsoluteFill>
  );
};

export const Promo: React.FC = () => {
  const f = useCurrentFrame();
  return <FrameContext.Provider value={f}><Scene /></FrameContext.Provider>;
};

