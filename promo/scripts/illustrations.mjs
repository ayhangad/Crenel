// Renders the app pictures used by the README (docs/media/ill-*.jpg) and the website
// (website/public/media/ill-*.webp): one 1600×1000 frame each, the notch over the wallpaper
// at a chosen moment of the film. Composition: "Illustration" in src/Illustration.tsx.
import { execFileSync } from 'node:child_process';
import { mkdirSync } from 'node:fs';
import { createRequire } from 'node:module';

const require = createRequire(new URL('../../website/package.json', import.meta.url));
const sharp = require('sharp');

const SHOTS = {
  meeting: { frame: 90 },
  today: { frame: 200 },
  dictation: { frame: 340 },
  inserted: { frame: 420 },
  call: { frame: 494 },
  recording: { frame: 600 },
  ready: { frame: 735 },
  tasks: { frame: 870 },
  window: { frame: 90, window: true },
};

mkdirSync('out/ill', { recursive: true });
for (const [name, props] of Object.entries(SHOTS)) {
  const png = `out/ill/${name}.png`;
  execFileSync('npx', ['remotion', 'still', 'Illustration', png, `--props=${JSON.stringify(props)}`], { stdio: 'inherit' });
  await sharp(png).jpeg({ quality: 88, mozjpeg: true }).toFile(`../docs/media/ill-${name}.jpg`);
  await sharp(png).webp({ quality: 88 }).toFile(`../website/public/media/ill-${name}.webp`);
}
