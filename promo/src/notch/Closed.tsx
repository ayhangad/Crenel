// Closed notch states: compact (ears) and strip (ears + one 38 pt line).
// Markup follows tpl-closed in docs/design/crenel-prototype.html.
import React from 'react';
import { Cells, FireLamp, Icon, Key, Ladder, Lamp, Orb, Seg, Telltale } from '../design/hud';
import { fmt, loops, noise, useF } from '../lib';
import { LINE1, LIVE1, T, W_MEETING, W_PROC, W_REC, WORDS, press, wordAt } from '../timeline';

const Ears: React.FC<{ w?: number; l: React.ReactNode; r: React.ReactNode }> = ({ w = 440, l, r }) => (
  <div className="ears" style={{ width: w }}>
    <div className="ear l">{l}</div>
    <div />
    <div className="ear r">{r}</div>
  </div>
);

const Peek: React.FC<{ ears: React.ReactNode; children: React.ReactNode }> = ({ ears, children }) => (
  <div className="peek">
    {ears}
    {children}
  </div>
);

/** A highlight sweeping the strip while its words are worked on (`.scanner`). */
const Scanner: React.FC<{ at: number }> = ({ at }) => {
  const f = useF();
  const t = ((f - at) / 30) / 1.6, k = Math.floor(t), fr = t - k, p = k % 2 === 0 ? fr : 1 - fr;
  const e = p < 0.5 ? 2 * p * p : 1 - Math.pow(-2 * p + 2, 2) / 2;
  return (
    <div className="absolute inset-0 overflow-hidden pointer-events-none" style={{ borderRadius: 'inherit' }}>
      <div className="absolute top-0 bottom-0" style={{ width: '22%', transform: `translateX(${-120 + 640 * e}%)`, background: 'linear-gradient(90deg, transparent, rgba(243,241,236,.16), transparent)' }} />
    </div>
  );
};

// ── 1 · Next meeting, 8 minutes out: amber, with the bottom edge as a fuse.
export const MeetingEars: React.FC = () => (
  <Ears w={W_MEETING}
    l={<><Telltale name="video" st="a" /><span className="ear-t text-ink-1">Design review</span></>}
    r={<span className="flex items-baseline text-signal"><Seg text="8" cells={2} h={13} /><span className="unit !text-signal/70">min</span></span>} />
);

// ── 3 · Dictation.
const dictLevel = (f: number) => (f < T.fnUp ? 0.35 + 0.65 * noise(f / 4.5, 3) : 0.1);

export const Stream: React.FC<{ text: string; caret?: boolean; dim?: boolean }> = ({ text, caret, dim }) => {
  const f = useF();
  return (
    <div className={`stream ${dim ? '!text-ink-3' : ''}`}>
      <span>{text}{caret && <span className="caret" style={{ opacity: loops.caret(f) }} />}</span>
    </div>
  );
};

const words = (n: number) => WORDS.slice(0, n).join(' ');
const wordsShown = (f: number) => WORDS.filter((_, i) => wordAt(i) <= f).length;

export const DictListening: React.FC = () => {
  const f = useF(), n = wordsShown(f);
  return (
    <Peek ears={<Ears l={<><Telltale name="mic" st="w" /><span className="text-ink-1">Listening</span></>} r={<Ladder level={0.6 + 0.6 * noise(f / 5, 2)} />} />}>
      <div className="strip"><Stream text={words(n)} caret /><span className="t-meta pr-2">Notes</span></div>
    </Peek>
  );
};

/** The live size: the orb breathes with the voice; up to three lines, newest at the bottom. */
export const DictLive: React.FC = () => {
  const f = useF(), n = wordsShown(f);
  const l1 = WORDS.slice(0, Math.min(n, LINE1)).join(' '), l2 = n > LINE1 ? WORDS.slice(LINE1, n).join(' ') : '';
  const caret = <span className="inline-block align-[-2px] ml-[3px] w-[6px] h-[14px] rounded-[1px]" style={{ background: '#aaa7a1', opacity: f < T.fnUp ? 1 : loops.caret(f) }} />;
  return (
    <Peek ears={<Ears l={<><Telltale name="mic" st="w" /><span className="text-ink-1">Listening</span></>} r={<Ladder level={0.6 + 0.6 * noise(f / 5, 2)} />} />}>
      <div className="mx-2 flex items-center gap-3 rounded-[12px] px-[10px] py-[9px] min-h-[38px]" style={{ background: 'rgba(255,255,255,.055)' }}>
        <span className="flex-none rounded-full overflow-hidden" style={{ width: 30, height: 30 }}><Orb size={30} level={dictLevel(f)} at={LIVE1} /></span>
        <div className="flex-1 min-w-0 t-body text-ink-1 whitespace-nowrap">
          <div>{l1}{!l2 && caret}</div>
          {l2 && <div>{l2}{caret}</div>}
        </div>
      </div>
    </Peek>
  );
};

export const DictWriting: React.FC = () => {
  const f = useF();
  return (
    <Peek ears={<Ears l={<><Icon id="i-mic" className="ico-s text-ink-2" style={{ opacity: loops.breathe(f) }} /><span>Writing</span></>} r={<Cells states={['done', 'cur', 'off']} />} />}>
      <div className="strip"><Stream text={WORDS.join(' ')} dim /><span className="t-meta pr-2">Notes</span><Scanner at={T.fnUp} /></div>
    </Peek>
  );
};

export const DictInserted: React.FC = () => (
  <Peek ears={<Ears l={<><Icon id="i-mic" className="ico-s text-ink-2" /><span>Inserted</span></>} r={<><FireLamp on="g" at={T.inserted + 4} /><span className="text-ink-1">Notes</span></>} />}>
    <div className="strip"><Stream text={WORDS.join(' ') + '.'} /><span className="w-1" /></div>
  </Peek>
);

// ── 4 · The call.
export const PromptOffer: React.FC = () => {
  const f = useF(), p = press(f, T.clickRec);
  return (
    <Peek ears={<Ears l={<><Telltale name="video" st="a" /><span className="ear-t text-ink-1">Zoom</span></>} r={<><Lamp on="a" opacity={loops.blink(f)} /><span className="text-ink-1">On a call</span></>} />}>
      <div className="strip">
        <span className="t-body">Record this call?</span><span className="t-meta">Partner call</span><span className="flex-1" />
        <Key kbd="esc">Not now</Key>
        <Key kind="primary" kbd="↩" pressed={p}><Lamp on="r" dot />Record</Key>
      </div>
    </Peek>
  );
};

/** Elapsed seconds: real time at first, then the meeting fast-forwards to 48:12. */
export const elapsedAt = (f: number) => {
  const p = Math.max(0, Math.min(1, (f - T.rec) / (T.clickStop - T.rec)));
  return Math.min(2892, (f - T.rec) / 30 + 2892 * Math.pow(p, 2.6));
};

export const RecordingEars: React.FC = () => {
  const f = useF();
  return (
    <Ears w={W_REC}
      l={<><Lamp on="r" dot opacity={loops.pulse(f)} /><Seg text={fmt(elapsedAt(f))} cells={5} h={13} className="text-ink-1" /></>}
      r={<Ladder seed={4} />} />
  );
};

// ── 5 · Processing, then the result.
export const ProcEars: React.FC = () => {
  const f = useF();
  const stage = f < T.transcribing ? 0 : f < T.summarizing ? 1 : 2;
  const word = ['Saving', 'Transcribing', 'Summarizing'][stage];
  const cells = [['cur', 'off', 'off', 'off'], ['done', 'done', 'cur', 'off'], ['done', 'done', 'done', 'cur']][stage];
  return (
    <Ears w={W_PROC}
      l={<><Icon id="i-transcript" className="ico-s text-ink-2" style={{ opacity: loops.breathe(f) }} /><span>{word}</span></>}
      r={<Cells states={cells} />} />
  );
};

export const ReadyStrip: React.FC = () => (
  <Peek ears={<Ears l={<><Icon id="i-transcript" className="ico-s text-ink-1" /><span className="ear-t text-ink-1">Design review</span></>} r={<><FireLamp on="g" at={T.ready + 6} /><span className="text-ink-1">Ready</span></>} />}>
    <div className="strip">
      <span className="t-body">Notes and 3 action items</span><span className="t-meta">48 min</span><span className="flex-1" />
      <Key kbd="esc">Later</Key>
      <Key kind="primary" kbd="↩">Open</Key>
    </div>
  </Peek>
);

/** The meeting fuse along the bottom edge. */
export const Fuse: React.FC<{ w: number; rb: number; v: number; opacity: number }> = ({ w, rb, v, opacity }) => (
  <i className="absolute bottom-0 left-1/2 h-[2px] rounded-[1px]" style={{ width: (w - 2 * rb) * v, transform: 'translateX(-50%)', opacity, background: '#ffad33', boxShadow: '0 0 8px #ffad33, 0 0 2px #ffad33' }} />
);

