import React from 'react';
import { FrameContext } from './lib';
import { Scene } from './Promo';

/** README hero: the Today panel from the film, without captions or pointer. */
export const Poster: React.FC = () => (
  <FrameContext.Provider value={200}><Scene still /></FrameContext.Provider>
);
