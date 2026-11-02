import { writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { d, shape, size, svg, transform } from './quill.mjs';

const here = dirname(fileURLToPath(import.meta.url));
export const colors = { ink: '#1B2235', paper: '#F5F0E6', vermilion: '#E0442B' };

const squircle = (x, y, w) => {
  const r = w * 0.225;
  return `M ${x + r} ${y} H ${x + w - r} C ${x + w - r * 0.4} ${y} ${x + w} ${y + r * 0.4} ${x + w} ${y + r} V ${y + w - r} C ${x + w} ${y + w - r * 0.4} ${x + w - r * 0.4} ${y + w} ${x + w - r} ${y + w} H ${x + r} C ${x + r * 0.4} ${y + w} ${x} ${y + w - r * 0.4} ${x} ${y + w - r} V ${y + r} C ${x} ${y + r * 0.4} ${x + r * 0.4} ${y} ${x + r} ${y} Z`;
};
const page = (body) => `<svg viewBox="0 0 1024 1024" width="1024" height="1024" xmlns="http://www.w3.org/2000/svg">${body}</svg>\n`;
const tile = `<path d="${squircle(100, 100, 824)}" fill="${colors.ink}"/><path d="${squircle(101, 101, 822)}" fill="none" stroke="#FFFFFF" stroke-opacity=".1" stroke-width="2"/>`;

writeFileSync(join(here, 'icon.svg'), page(tile + svg({ ink: colors.paper, tip: colors.vermilion }, 512, 512, 0.82)));
writeFileSync(join(here, 'mark.svg'), page(svg({ ink: colors.paper, tip: colors.vermilion }, 512, 512, 1.3)));
writeFileSync(join(here, 'mark-ink.svg'), page(svg({ ink: colors.ink, tip: colors.vermilion }, 512, 512, 1.3)));

const T = transform(500, 500, 980 / size);
const point = (p) => T(p).map((n) => Math.round(n * 10) / 10);
writeFileSync(join(here, '../../Sources/Quill/Brand/mark.json'), JSON.stringify({
  vane: `${d(shape.vane, T)} ${d(shape.rachis, T)}`,
  nib: d(shape.nib, T),
  from: point([-1, 488]),
  to: point([0, -480]),
}));
