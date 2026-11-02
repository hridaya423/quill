import { writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { barbs, feather, spline } from './feather.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const out = (name, text) => writeFileSync(join(here, name), text);

export const spectrum = [[0, '#FFD08A'], [0.25, '#FF8A3D'], [0.55, '#FF3F5E'], [0.8, '#C2338F'], [1, '#6E4BFF']];

const path = spline([[701, 586], [732, 470], [701, 354], [616, 269], [500, 238], [384, 269], [299, 354], [268, 470], [299, 586], [384, 671], [500, 702], [612, 716], [716, 760], [812, 830]]);
const hero = { width: 106, inner: 0.34, barbs: 340, stroke: 2.5, alpha: 0.96, curl: 0.24, angle: 0.66, shaftWidth: 5, nib: 3, vane: 0.775,
  shaftOpacity: 0.92, jitter: 1, splits: [[0.22, 1], [0.41, 1], [0.6, 1]], colors: spectrum };
const bold = { ...hero, barbs: 120, stroke: 11, width: 120, inner: 0.45, jitter: 0, splits: [], shaftWidth: 0.1, nib: 260, shaftOpacity: 1, alpha: 1 };

const defs = `
<linearGradient id="ink" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#2B2521"/><stop offset="1" stop-color="#0F0C0B"/></linearGradient>
<radialGradient id="ember" cx=".5" cy=".5" r=".5"><stop offset="0" stop-color="#FF7A3A" stop-opacity=".9"/><stop offset=".5" stop-color="#E8307A" stop-opacity=".35"/><stop offset="1" stop-color="#7A4DFF" stop-opacity="0"/></radialGradient>
<linearGradient id="sheen" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff" stop-opacity=".14"/><stop offset=".45" stop-color="#fff" stop-opacity="0"/></linearGradient>
<filter id="soft" filterUnits="userSpaceOnUse" x="0" y="0" width="1024" height="1024"><feGaussianBlur stdDeviation="50"/></filter>
<clipPath id="tile"><rect x="100" y="100" width="824" height="824" rx="186"/></clipPath>`;

const svg = (body) => `<svg viewBox="0 0 1024 1024" width="1024" height="1024" xmlns="http://www.w3.org/2000/svg"><defs>${defs}</defs>${body}</svg>\n`;

const tile = (body) => `<g clip-path="url(#tile)"><rect x="100" y="100" width="824" height="824" fill="url(#ink)"/>${body}<rect x="100" y="100" width="824" height="824" fill="url(#sheen)"/></g>
<rect x="101" y="101" width="822" height="822" rx="185" fill="none" stroke="#ffffff14" stroke-width="2"/>`;

const glow = `<circle cx="500" cy="470" r="250" fill="url(#ember)" filter="url(#soft)" opacity=".55"/>`;
const nibGlow = `<circle cx="800" cy="818" r="56" fill="#FF6A3A" filter="url(#soft)" opacity=".85"/>`;

out('icon.svg', svg(tile(`<g transform="translate(14 22)">${glow}${nibGlow}${feather(path, hero)}<circle cx="811" cy="829" r="5" fill="#FFE2C2"/></g>`)));
out('icon-small.svg', svg(tile(`<g transform="translate(14 22)">${glow}${feather(path, bold)}</g>`)));
out('mark.svg', svg(`<g transform="translate(14 22)">${feather(path, hero)}<circle cx="811" cy="829" r="5" fill="#FFE2C2"/></g>`));
writeFileSync(join(here, '../../Sources/Quill/Brand/feather.json'), JSON.stringify(barbs(path, hero)));
