// Segment numerals (drawSeg in docs/design/crenel-prototype.html): a 10×18 cell, 2-unit
// strokes, hexagonal segments with a 0.55 gap, 7° italic, ghost "8" behind every digit.
// Shared by the Astro component (static) and the live notch script (browser).
const G = 0.55;
const H = (x1: number, x2: number, y: number) => `${x1},${y} ${x1 + 1},${y - 1} ${x2 - 1},${y - 1} ${x2},${y} ${x2 - 1},${y + 1} ${x1 + 1},${y + 1}`;
const V = (x: number, y1: number, y2: number) => `${x},${y1} ${x + 1},${y1 + 1} ${x + 1},${y2 - 1} ${x},${y2} ${x - 1},${y2 - 1} ${x - 1},${y1 + 1}`;
const SEGS: Record<string, string> = {
  a: H(1 + G, 9 - G, 1), b: V(9, 1 + G, 9 - G), c: V(9, 9 + G, 17 - G), d: H(1 + G, 9 - G, 17),
  e: V(1, 9 + G, 17 - G), f: V(1, 1 + G, 9 - G), g: H(1 + G, 9 - G, 9),
};
const MAP: Record<string, string> = { 0: 'abcdef', 1: 'bc', 2: 'abged', 3: 'abgcd', 4: 'fgbc', 5: 'afgcd', 6: 'afgedc', 7: 'abc', 8: 'abcdefg', 9: 'abcdfg', '-': 'g', ' ': '' };

/** Returns the SVG markup for `text` at height `h` (px), padded with ghost cells. */
export function segSVG(text: string, h = 14, cells = 0): string {
  if (cells && text.length < cells) text = ' '.repeat(cells - text.length) + text;
  let x = 0;
  let parts = '';
  for (const ch of text) {
    if (ch === ':' || ch === '.') {
      for (const y of ch === ':' ? [5.5, 12.5] : [16.5]) parts += `<rect x="${x + 1}" y="${y - 1}" width="2" height="2" rx="0.4"/>`;
      x += 5;
      continue;
    }
    const on = MAP[ch] ?? '';
    for (const k in SEGS) parts += `<polygon points="${SEGS[k]}" transform="translate(${x} 0)" class="${on.includes(k) ? 'on' : 'g'}"/>`;
    x += 13;
  }
  const w = x - 3 + 2.6;
  return `<svg viewBox="0 0 ${w} 18" height="${h}" width="${+((w / 18) * h).toFixed(1)}" fill="currentColor" aria-hidden="true"><g transform="translate(2.2 0) skewX(-7)">${parts}</g></svg>`;
}
