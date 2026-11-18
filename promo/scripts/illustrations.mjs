// Renders the app pictures used by the README (docs/media/ill-*.jpg) and the website
// (website/public/media/ill-*.webp): one 1600×1000 frame each, the notch over the wallpaper
// at a chosen moment of the film. `crop` is how many film points the picture spans: the
// notch is drawn large, not at real screen scale, and open panels get a wider crop to fit.
// Composition: "Illustration" in src/Illustration.tsx.
import { execFileSync } from 'node:child_process';
import { mkdirSync } from 'node:fs';
import { createRequire } from 'node:module';

const require = createRequire(new URL('../../website/package.json', import.meta.url));
const sharp = require('sharp');

const SHOTS = {
  meeting: { frame: 90, crop: 500 },
  today: { frame: 200, crop: 840 },
  dictation: { frame: 340, crop: 500 },
  inserted: { frame: 420, crop: 500 },
  call: { frame: 494, crop: 500 },
  recording: { frame: 600, crop: 690 },
  ready: { frame: 735, crop: 500 },
  tasks: { frame: 870, crop: 830 },
  window: { frame: 90, window: true },
};

mkdirSync('out/ill', { recursive: true });
for (const [name, props] of Object.entries(SHOTS)) {
  const png = `out/ill/${name}.png`;
  execFileSync('npx', ['remotion', 'still', 'Illustration', png, `--props=${JSON.stringify(props)}`], { stdio: 'inherit' });
  await sharp(png).jpeg({ quality: 88, mozjpeg: true }).toFile(`../docs/media/ill-${name}.jpg`);
  await sharp(png).webp({ quality: 88 }).toFile(`../website/public/media/ill-${name}.webp`);
}
