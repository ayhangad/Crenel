import React from 'react';
import { getInputProps, staticFile } from 'remotion';
import { FrameContext } from './lib';
import { Scene } from './Promo';
import { camAt } from './timeline';

// One frame size for every picture of the notch (README and website): a 16:10 crop of the
// film's top centre, the notch hanging from the top edge over the living wallpaper. The
// film's camera zoom is cancelled; each shot picks its own crop (see scripts/illustrations.mjs).
export const ILLUSTRATION = { width: 1600, height: 1000 };
type Props = { frame?: number; window?: boolean; crop?: number };

export const Illustration: React.FC = () => {
  const { frame = 200, window: showWindow = false, crop = 1100 } = getInputProps() as Props;
  const K = ILLUSTRATION.width / crop; // crop = film points shown across the picture
  const s = camAt(frame);
  return (
    <FrameContext.Provider value={frame}>
      <div style={{ position: 'absolute', inset: 0, overflow: 'hidden', background: '#fbf8fb' }}>
        <div style={{ position: 'absolute', left: 0, top: 0, width: 1920, height: 1080, transformOrigin: '0 0', transform: `translateX(${ILLUSTRATION.width / 2 - 960 * K}px) scale(${K})` }}>
          <div style={{ position: 'absolute', inset: 0, transformOrigin: '960px 0px', transform: `scale(${1 / s})` }}>
            <Scene still />
          </div>
        </div>
        {showWindow && (
          <img
            src={staticFile('desktop-today.png')}
            style={{ position: 'absolute', left: '50%', top: 150, width: 1240, transform: 'translateX(-50%)', borderRadius: 18, boxShadow: '0 0 0 1px rgba(0,0,0,.85), 0 50px 100px -30px rgba(10,40,60,.55), 0 20px 40px -20px rgba(0,0,0,.45)' }}
          />
        )}
      </div>
    </FrameContext.Provider>
  );
};
