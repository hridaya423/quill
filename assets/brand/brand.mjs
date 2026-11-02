import { writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { aperture, q, uill, wordmark, svg } from './quill.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const bundle = join(here, '../../Sources/Quill/Brand');
const sky = '#B7D6F4', blue = '#396899', cloud = '#F8FAFC';

const box = (path, pad) => {
  const v = path.match(/-?\d+(\.\d+)?/g).map(Number);
  const xs = v.filter((_, i) => i % 2 === 0), ys = v.filter((_, i) => i % 2 === 1);
  const x = Math.min(...xs) - pad, y = Math.min(...ys) - pad;
  return `${x} ${y} ${Math.max(...xs) + pad - x} ${Math.max(...ys) + pad - y}`;
};
const page = (body, view) => `<svg viewBox="${view}" xmlns="http://www.w3.org/2000/svg">${body}</svg>\n`;
const square = (path) => {
  const [x, y, w, h] = box(path, 24).split(' ').map(Number), s = Math.max(w, h);
  return `${x - (s - w) / 2} ${y - (s - h) / 2} ${s} ${s}`;
};

const tile = `<defs><linearGradient id="t" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#FFFFFF"/><stop offset="1" stop-color="#EEF4FB"/></linearGradient></defs>`
  + `<rect x="100" y="100" width="824" height="824" rx="185.4" fill="url(#t)"/>`
  + `<rect x="100.5" y="100.5" width="823" height="823" rx="185" fill="none" stroke="${sky}" stroke-opacity=".55"/>`;
writeFileSync(join(here, 'icon.svg'), page(tile + `<g transform="translate(500 480) scale(.73)">${svg(aperture, blue)}</g>`, '0 0 1024 1024'));
writeFileSync(join(here, 'mark.svg'), page(svg(aperture, cloud), square(aperture)));
writeFileSync(join(here, 'mark-ink.svg'), page(svg(aperture, blue), square(aperture)));
writeFileSync(join(here, 'wordmark.svg'), page(svg(wordmark, blue), box(wordmark, 24)));
writeFileSync(join(bundle, 'mark.json'), JSON.stringify({ path: aperture, q, uill, wordmark }));

const [wx, wy, ww, wh] = box(wordmark, 0).split(' ').map(Number);
const ws = 44 / wh;
const lockup = `<g transform="translate(${330 - (wx + ww / 2) * ws} ${58 - wy * ws}) scale(${ws})">${svg(wordmark, blue)}</g>`;
const backdrop = `<svg viewBox="0 0 660 420" width="660" height="420" xmlns="http://www.w3.org/2000/svg">`
  + `<defs><linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop stop-color="${cloud}"/><stop offset="1" stop-color="#EEF4FB"/></linearGradient>`
  + `<linearGradient id="planet" x1="0" y1="0" x2="0" y2="1"><stop stop-color="${sky}"/><stop offset=".25" stop-color="#DCEAF8"/><stop offset="1" stop-color="${cloud}"/></linearGradient></defs>`
  + `<rect width="660" height="420" fill="url(#bg)"/>`
  + `<ellipse cx="330" cy="760" rx="560" ry="390" fill="url(#planet)"/>`
  + `<ellipse cx="330" cy="760" rx="560" ry="390" fill="none" stroke="${sky}" stroke-width="2"/>`
  + lockup
  + `<path d="M 262 196 C 300 168 360 168 398 196" fill="none" stroke="${blue}" stroke-width="2.5" stroke-linecap="round" stroke-dasharray="1 9"/>`
  + `<path d="M 393.6 184.8 L 398 196 L 386 195.1" fill="none" stroke="${blue}" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/>`
  + `<text x="330" y="398" text-anchor="middle" font-family="-apple-system, 'SF Pro Rounded', system-ui" font-size="12.5" font-weight="500" fill="#4C5F73">Drag Quill into Applications</text>`
  + `</svg>\n`;
writeFileSync(join(here, '../dmg/background.svg'), backdrop);

const night = '#091019';
const banner = (dark) => {
  const s = 150 / wh;
  const mark = `<g transform="translate(${640 - (wx + ww / 2) * s} ${108 - wy * s}) scale(${s})">${svg(wordmark, dark ? sky : blue)}</g>`;
  const fill = dark ? night : cloud;
  const rim = dark
    ? `<radialGradient id="air" cx="640" cy="400" r="640" gradientUnits="userSpaceOnUse"><stop stop-color="${blue}" stop-opacity=".55"/><stop offset="1" stop-color="${blue}" stop-opacity="0"/></radialGradient>`
      + `<linearGradient id="land" x1="0" y1="0" x2="0" y2="1"><stop stop-color="${sky}"/><stop offset=".06" stop-color="${blue}"/><stop offset=".35" stop-color="#122135"/><stop offset="1" stop-color="${night}"/></linearGradient>`
    : `<radialGradient id="air" cx="640" cy="400" r="640" gradientUnits="userSpaceOnUse"><stop stop-color="${sky}" stop-opacity=".45"/><stop offset="1" stop-color="${sky}" stop-opacity="0"/></radialGradient>`
      + `<linearGradient id="land" x1="0" y1="0" x2="0" y2="1"><stop stop-color="${sky}"/><stop offset=".3" stop-color="#DCEAF8"/><stop offset="1" stop-color="${cloud}"/></linearGradient>`;
  return `<svg viewBox="0 0 1280 400" width="1280" height="400" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="Quill: a Mac Markdown editor where AI co-writers edit your draft in place">`
    + `<defs>${rim}</defs><rect width="1280" height="400" rx="24" fill="${fill}"/>`
    + `<rect width="1280" height="400" rx="24" fill="url(#air)"/>`
    + `<ellipse cx="640" cy="1210" rx="1100" ry="860" fill="url(#land)"/>`
    + `<ellipse cx="640" cy="1210" rx="1100" ry="860" fill="none" stroke="${sky}" stroke-width="${dark ? 2.5 : 2}" stroke-opacity="${dark ? 1 : .9}"/>`
    + mark + `</svg>\n`;
};
writeFileSync(join(here, '../../.github/assets/banner-light.svg'), banner(false));
writeFileSync(join(here, '../../.github/assets/banner-dark.svg'), banner(true));
