import React, { useEffect, useState } from 'react';
import { continueRender, delayRender, staticFile } from 'remotion';

const FACES: [string, string][] = [
  ['400', 'fonts/Geist-Regular.ttf'],
  ['500', 'fonts/Geist-Medium.ttf'],
  ['600', 'fonts/Geist-SemiBold.ttf'],
];

let loading: Promise<void> | null = null;
const load = () =>
  (loading ??= Promise.all(
    FACES.map(async ([weight, file]) => {
      const face = new FontFace('Geist', `url(${staticFile(file)}) format('truetype')`, { weight });
      await face.load();
      document.fonts.add(face);
    }),
  ).then(() => undefined));

/** Renders its children only once Geist is in, so layout and measuring see the real font. */
export const FontGate: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [ready, setReady] = useState(false);
  const [handle] = useState(() => delayRender('Loading Geist'));
  useEffect(() => {
    load().then(() => { setReady(true); continueRender(handle); });
  }, [handle]);
  return ready ? <>{children}</> : null;
};
