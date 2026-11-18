// Open notch panels (560 pt): Today, Recording, Tasks.
// Markup follows tpl-band, tpl-today, tpl-recording and tpl-tasks-body in the prototype;
// the band with its own tab row follows the app's current render (artifacts/ui-audit).
import React, { useLayoutEffect, useRef, useState } from 'react';
import { Chart, Gauge, Icon, Key, Lamp, Ramp, Ruler, Seg, Telltale, Vu, ignite } from '../design/hud';
import { EASE, fmt, lerp, loops, prog, useF } from '../lib';
import { CHIP1, CHIP2, T, press, typedAt } from '../timeline';
import { elapsedAt } from './Closed';

/** `[data-stagger]`: sections drop in 5 pt from above, one after another. */
const Stagger: React.FC<{ at: number; i: number; children: React.ReactNode; className?: string }> = ({ at, i, children, className }) => {
  const f = useF(), p = prog(f, at + 2 + i * 2.2, at + 13 + i * 2.2, EASE.enter);
  return <div className={className} style={{ opacity: p, transform: `translateY(${(1 - p) * -6}px)` }}>{children}</div>;
};

const TABS = ['Today', 'Recordings', 'Tasks'];

/** The camera band (mark, tools) and the tab row with its sliding lamp. */
const Band: React.FC<{ tab: number; from?: number; at?: number }> = ({ tab, from = tab, at = 0 }) => {
  const f = useF();
  const refs = useRef<(HTMLSpanElement | null)[]>([]);
  const [pos, setPos] = useState<{ x: number; w: number }[] | null>(null);
  useLayoutEffect(() => {
    setPos(refs.current.map((el) => {
      const label = el?.querySelector('[data-label]') as HTMLElement | null;
      return { x: el?.offsetLeft ?? 0, w: label?.offsetWidth ?? el?.offsetWidth ?? 0 };
    }));
  }, []);
  const p = prog(f, at, at + 10, EASE.tabLamp);
  const lamp = pos ? { x: lerp(pos[from].x, pos[tab].x, p), w: lerp(pos[from].w, pos[tab].w, p) } : null;
  const on = p > 0.5 ? tab : from;
  return (
    <>
      <div className="band !mb-0">
        <span className="nb"><svg><use href="#i-mark" /></svg>Crenel</span>
        <div />
        <div className="band-r">
          <span className="btn-icon"><Icon id="i-window" /></span>
          <span className="btn-icon"><Icon id="i-pin" style={{ transform: 'rotate(30deg)' }} /></span>
        </div>
      </div>
      <div className="tabs mb-2" style={{ display: 'flex' }}>
        {TABS.map((t, i) => (
          <span key={t} ref={(el) => { refs.current[i] = el; }} className={`tab ${i === on ? 'on' : ''}`}>
            <span data-label>{t}</span>{t === 'Tasks' && <span className="badge">5</span>}
          </span>
        ))}
        {lamp && <i className="tab-lamp" style={{ left: lamp.x, width: lamp.w }} />}
      </div>
    </>
  );
};

const Panel: React.FC<{ children: React.ReactNode }> = ({ children }) => (
  <div style={{ width: 560, padding: '0 14px 16px' }}>{children}</div>
);

// ── Today: the next event as one instrument, the console, the day ruler, the agenda.
const Row: React.FC<{ time: string; icon: string; title: string; meta: string; extra?: React.ReactNode; dim?: boolean }> = ({ time, icon, title, meta, extra, dim }) => (
  <div className={`row ${dim ? 'opacity-55' : ''}`}>
    <div className="tcol"><b>{time}</b></div>
    <Icon id={icon} className="ico-s text-ink-3 mt-[1px]" />
    <div className="flex-1 min-w-0 flex flex-col gap-[3px]"><span className="t-body truncate">{title}</span><span className="t-meta truncate">{meta}</span></div>
    {extra}
  </div>
);

export const TodayPanel: React.FC = () => {
  const f = useF(), at = T.open1;
  return (
    <Panel>
      <Band tab={0} />
      <div className="flex flex-col">
        <Stagger at={at} i={0}>
          <div className="hero">
            <div className="gauge-box bleed text-signal">
              <Gauge id="g-today" v={ignite(f, at + 6, 0.133)} zones="0-2:r" className="text-signal" />
              <div className="gauge-c"><Seg text="8" cells={2} h={24} className="text-signal" /><span className="t-micro !text-signal/70">min</span></div>
            </div>
            <div className="flex-1 min-w-0 flex flex-col gap-1.5">
              <span className="t-hero truncate">Design review</span>
              <div className="l2"><span>10:50</span><span className="sep">·</span><span>Google Meet</span></div>
              <div className="l2"><Icon id="i-people" className="ico-xs text-ink-4" /><span>Deniz, Ece and 2 others</span></div>
            </div>
          </div>
        </Stagger>
        <Stagger at={at} i={1}>
          <div className="console mx-0.5 mb-3">
            <span className="note"><Lamp on="g" /><span>Crenel will ask to record when it starts</span></span>
            <Key kbd="⌘R"><Lamp on="r" dot />Record</Key>
            <Key kind="primary" kbd="⌘J">Join</Key>
          </div>
        </Stagger>
        <Stagger at={at} i={2}>
          <Ruler span={[8, 20]} now={10.7} events="10.83-11.5:amber|16-17|17.5-18:invite|19-20:dim" />
        </Stagger>
        <Stagger at={at} i={3} className="mt-1">
          <div className="group-h">Today<span className="n">3</span></div>
          <Row time="16:00" icon="i-place" title="Lunch with Deniz" meta="Karaköy Lokantası" />
          <Row time="17:30" icon="i-video" title="Partner call" meta="Zoom · from Mira Lund"
            extra={<span className="flex items-center gap-2 t-meta text-ink-2 mt-[2px]"><span className="sg a"><svg viewBox="0 0 16 16"><use href="#s-warn" /></svg></span>Invite</span>} />
          <Row time="19:00" icon="i-calendar" title="Gym" meta="Personal" dim />
        </Stagger>
      </div>
    </Panel>
  );
};

// ── Recording: elapsed time as the hero, the plan ramp, a chart recorder and two meters.
export const RecordingPanel: React.FC = () => {
  const f = useF(), at = T.open2, e = elapsedAt(f), stop = press(f, T.clickStop);
  return (
    <Panel>
      <Band tab={0} />
      <div className="flex flex-col">
        <Stagger at={at} i={0}>
          <div className="flex items-center gap-4 px-[10px] pt-1">
            <div className="flex-1 flex flex-col gap-2.5 bleed text-live">
              <div className="flex items-center gap-2"><Lamp on="r" dot opacity={loops.pulse(f)} /><span className="t-label text-ink-1">Recording</span><span className="t-meta">Design review</span></div>
              <Seg text={fmt(e)} cells={5} h={34} className="text-ink-1" />
              <div className="flex items-end gap-2.5"><Ramp sec={e} plan={3600} max={4500} w={196} /><span className="t-micro -mb-[1px]">of 60 min</span></div>
            </div>
            <span className="knob"><Icon id="i-mic" /><Lamp on="w" /></span>
            <span className="knob" style={{ transform: `scale(${1 - 0.06 * stop})`, filter: `brightness(${1 + 0.4 * stop})` }}><Icon id="i-stop" className="ico text-live" /></span>
          </div>
        </Stagger>
        <Stagger at={at} i={1} className="px-[10px] mt-5">
          <Chart at={at} />
          <div className="flex justify-between t-micro mt-1.5"><span>−2:00</span><span>−1:00</span><span>now</span></div>
        </Stagger>
        <Stagger at={at} i={2} className="flex flex-col gap-1 mt-4">
          <div className="flex items-center gap-3 px-[10px] h-8"><Telltale name="mic" st="w" /><span className="t-label text-ink-2 w-[96px]">Your mic</span><Vu seed={11} gain={0.85} /></div>
          <div className="flex items-center gap-3 px-[10px] h-8"><Telltale name="speaker" st="w" /><span className="t-label text-ink-2 w-[96px]">The call</span><Vu seed={23} /></div>
        </Stagger>
        <Stagger at={at} i={3}>
          <div className="flex items-center gap-3 px-[10px] h-8 mt-2"><Telltale name="accessibility" st="g" /><span className="t-meta">Your mic follows mute in Zoom</span></div>
        </Stagger>
      </div>
    </Panel>
  );
};

// ── Tasks: one line in, parsed as you type, saved to Reminders.
const Mark: React.FC<{ m: string }> = ({ m }) => <span className="flex-none w-4 h-4 flex items-center justify-center"><svg className="ico"><use href={`#m-${m}`} /></svg></span>;
const Pri: React.FC<{ n: number; tint: string }> = ({ n, tint }) => <span className={`pri ${tint}`}>{[1, 2, 3].map((i) => <i key={i} className={i <= n ? 'on' : ''} />)}</span>;
const TRow: React.FC<{ m: string; title: string; children?: React.ReactNode; style?: React.CSSProperties }> = ({ m, title, children, style }) => (
  <div className="trow" style={style}><Mark m={m} /><span className="flex-1 min-w-0 flex items-center gap-2.5"><span className="t-body flex-1 truncate">{title}</span>{children}</span></div>
);

const Chip: React.FC<{ at: number; children: React.ReactNode }> = ({ at, children }) => {
  const f = useF(), p = prog(f, at, at + 8, EASE.tabLamp);
  return (
    <span className="chip" style={{ opacity: Math.min(1, p * 1.5), transform: `scale(${0.85 + 0.15 * p})`, transformOrigin: 'left center' }}>
      {children}<svg className="w-2 h-2 text-ink-4 ml-0.5"><use href="#i-close" /></svg>
    </span>
  );
};

export const TasksPanel: React.FC = () => {
  const f = useF(), at = T.open3;
  const typed = f >= T.enter ? '' : typedAt(f);
  const chips = f >= CHIP1 && f < T.enter;
  const chipsH = f < T.enter ? 30 * prog(f, CHIP1, CHIP1 + 8, EASE.enter) : 30 * (1 - prog(f, T.enter, T.enter + 8, EASE.enter));
  const added = prog(f, T.enter, T.enter + 11, EASE.rowSlide), flash = prog(f, T.enter, T.enter + 14, EASE.enter);
  const enterKey = press(f, T.enter);
  return (
    <Panel>
      <Band tab={2} from={0} at={at + 10} />
      <div className="flex flex-col">
        <Stagger at={at} i={0} className="mb-2">
          <div className="flex items-center gap-3 px-[10px] h-11 rounded-[12px]" style={{ background: 'rgba(255,255,255,.08)' }}>
            <Icon id="i-plus" className="ico-s text-ink-1" />
            <div className="relative flex-1 h-full flex items-center t-body whitespace-pre">
              {typed ? <span className="text-ink-1">{typed}</span> : <span className="text-ink-3">Add a task</span>}
              <span className="inline-block w-[1.5px] h-[15px] bg-ink-1 ml-[1px]" style={{ opacity: f > at + 14 ? (f >= T.typeFrom && f < T.enter ? 1 : loops.caret(f)) : 0, order: typed ? 0 : -1 }} />
            </div>
            <span className="t-micro" style={{ color: enterKey ? '#f3f1ec' : '#76736e' }}>↩</span>
          </div>
          <div className="flex gap-1 px-[6px] overflow-hidden items-end" style={{ height: chipsH }}>
            {chips && <Chip at={CHIP1}><span className="lamp on-a" />{f >= CHIP2 ? 'Tomorrow 15:00' : 'Tomorrow'}</Chip>}
          </div>
        </Stagger>
        <Stagger at={at} i={1}>
          <div className="group-h"><span>Today</span><span className="flex-1" /><span className="cells"><i className="on" /><i /><i /><i /><i /></span></div>
          <TRow m="progress" title="Write release notes"><span className="flex items-baseline text-signal"><Seg text="25" h={10} /><span className="unit !text-signal/70 !text-[10px]">min</span></span></TRow>
          <TRow m="blocked" title="Ship notarized build"><span className="t-meta">waiting on QA</span></TRow>
          <TRow m="open" title="Reply to Deniz about pricing"><Pri n={3} tint="text-signal" /><span className="t-meta text-live">Yesterday</span></TRow>
        </Stagger>
        <Stagger at={at} i={2}>
          <div className="group-h mt-2">Later<span className="n">{f >= T.enter + 4 ? 3 : 2}</span></div>
          <div style={{ height: 38 * added, overflow: 'hidden' }}>
            <TRow m="open" title="Call mom" style={{ opacity: added, transform: `translateY(${(1 - added) * -10}px)`, filter: `brightness(${lerp(2, 1, flash)})` }}>
              <span className="t-meta">Wed 15:00</span>
            </TRow>
          </div>
          <TRow m="open" title="Water the plants"><Icon id="i-repeat" className="ico-xs text-ink-4" /><span className="t-meta">Wed</span></TRow>
          <TRow m="open" title="Plan Q1 roadmap"><Pri n={2} tint="text-ink-2" /><span className="t-meta">Mon 23</span></TRow>
        </Stagger>
        <Stagger at={at} i={3}>
          <div className="actions mt-3 pl-[10px] pr-0.5">
            <span className="note"><Lamp on="g" />Synced with Reminders</span>
            <Key><Icon id="i-history" className="ico-xs" />Finished</Key>
          </div>
        </Stagger>
      </div>
    </Panel>
  );
};

