import React from 'react';
import { Composition, Still } from 'remotion';
import { FontGate } from './fonts';
import { Promo } from './Promo';
import { Poster } from './Poster';
import { DURATION } from './timeline';

const Gated = (C: React.FC) => () => <FontGate><C /></FontGate>;

export const Root: React.FC = () => (
  <>
    <Composition id="CrenelPromo" component={Gated(Promo)} durationInFrames={DURATION} fps={30} width={1920} height={1080} />
    <Still id="Poster" component={Gated(Poster)} width={1920} height={1080} />
  </>
);
