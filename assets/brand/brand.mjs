import { writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { curve, hairline, oval, ribbon } from './nib.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const smooth = (a, b, x) => {
  const t = Math.min(1, Math.max(0, (x - a) / (b - a)));
  return t * t * (3 - 2 * t);
};

export const colors = { ink: '#15120F', paper: '#F4EADB', ember: '#FF5B36' };

const nib = { nib: 104, angle: 0.62 };
const shape = { cx: 498, cy: 466, rx: 196, ry: 246, tilt: 0.16 };
const from = hairline(shape, nib.angle, -Math.PI * 0.74);
const bowl = oval({ ...shape, from, sweep: -Math.PI * 2 });
const tail = curve([420, 656], [520, 736], [680, 746], [846, 836]);
const dip = 0.815;
const tailPressure = (u) => 0.62 * smooth(0, 0.3, u) * (1 - 0.99 * smooth(0.3, 1, u) ** 0.9);

const mark = (fill) =>
  `<path d="${ribbon(bowl, { ...nib, pressure: () => 1 })}" fill="${fill}"/>` +
  `<path d="${ribbon(tail, { ...nib, pressure: tailPressure }, [0, dip + 0.005])}" fill="${fill}"/>` +
  `<path d="${ribbon(tail, { ...nib, pressure: tailPressure }, [dip, 1])}" fill="${colors.ember}"/>`;

const svg = (body) => `<svg viewBox="0 0 1024 1024" width="1024" height="1024" xmlns="http://www.w3.org/2000/svg">${body}</svg>\n`;
const tile = `<defs><linearGradient id="light" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#211C18"/><stop offset=".5" stop-color="${colors.ink}"/></linearGradient></defs>
<rect x="100" y="100" width="824" height="824" rx="186" fill="url(#light)"/>
<rect x="101" y="101" width="822" height="822" rx="185" fill="none" stroke="#FFFFFF" stroke-opacity=".07" stroke-width="2"/>`;

writeFileSync(join(here, 'icon.svg'), svg(tile + mark(colors.paper)));
writeFileSync(join(here, 'mark.svg'), svg(mark(colors.paper)));
writeFileSync(join(here, 'mark-ink.svg'), svg(mark(colors.ink)));

const sample = (pts, pressure) => {
  const lens = [0];
  for (let i = 1; i < pts.length; i++) lens.push(lens[i - 1] + Math.hypot(pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1]));
  const total = lens[lens.length - 1];
  return pts.filter((_, i) => i % 3 === 0 || i === pts.length - 1).map((p) => {
    const i = pts.indexOf(p);
    return [Math.round(p[0] * 10) / 10, Math.round(p[1] * 10) / 10, Math.round(pressure(lens[i] / total) * 1000) / 1000];
  });
};
writeFileSync(join(here, '../../Sources/Quill/Brand/mark.json'),
  JSON.stringify({ nib: nib.nib, angle: nib.angle, dip, bowl: sample(bowl, () => 1), tail: sample(tail, tailPressure) }));
