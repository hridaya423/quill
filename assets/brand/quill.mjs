const f = (v) => String(Math.round(v * 10) / 10);
const at = (c, r, a) => [c[0] + r * Math.cos(a), c[1] + r * Math.sin(a)];

class Pen {
  constructor() { this.out = []; }
  move(p) { this.out.push(`M ${f(p[0])} ${f(p[1])}`); this.at = p; return this; }
  line(p) { this.out.push(`L ${f(p[0])} ${f(p[1])}`); this.at = p; return this; }
  arc(c, r, a0, a1) {
    const n = Math.ceil(Math.abs(a1 - a0) / (Math.PI / 2) - 1e-9);
    const step = (a1 - a0) / n, k = (4 / 3) * Math.tan(step / 4) * r;
    for (let i = 0; i < n; i++) {
      const a = a0 + step * i, b = a + step;
      const p0 = at(c, r, a), p3 = at(c, r, b);
      const p1 = [p0[0] - k * Math.sin(a), p0[1] + k * Math.cos(a)];
      const p2 = [p3[0] + k * Math.sin(b), p3[1] - k * Math.cos(b)];
      this.out.push(`C ${f(p1[0])} ${f(p1[1])} ${f(p2[0])} ${f(p2[1])} ${f(p3[0])} ${f(p3[1])}`);
    }
    this.at = at(c, r, a1);
    return this;
  }
  close() { this.out.push('Z'); return this; }
  toString() { return this.out.join(' '); }
}

const angle = (c, p) => Math.atan2(p[1] - c[1], p[0] - c[0]);
const sweep = (a0, a1, via) => {
  const norm = (x) => ((x % (2 * Math.PI)) + 2 * Math.PI) % (2 * Math.PI);
  const up = norm(a1 - a0), mid = norm(via - a0);
  return mid <= up ? a0 + up : a0 - (2 * Math.PI - up);
};

const R = 330, r = 180, tilt = Math.PI / 3, offset = 33;
const shoulder = 104, hole = 452, reach = 160, slit = 7, breather = 27;
const d = [Math.cos(tilt), Math.sin(tilt)], n = [Math.sin(tilt), -Math.cos(tilt)];
const pt = (a, p) => [a * d[0] + (offset + p) * n[0], a * d[1] + (offset + p) * n[1]];
const along = (radius, p) => Math.sqrt(radius * radius - (offset + p) ** 2);

function mark() {
  const O = [0, 0], H = pt(hole, 0), gap = Math.sqrt(breather ** 2 - slit ** 2);
  const ringL = pt(along(R, -shoulder), -shoulder), ringR = pt(along(R, shoulder), shoulder);
  const counterR = pt(along(r, slit), slit), counterL = pt(along(r, -slit), -slit);
  const nAngle = Math.atan2(n[1], n[0]);
  const pen = new Pen().move(ringL);
  const a0 = angle(O, ringL);
  pen.arc(O, R, a0, sweep(a0, angle(O, ringR), a0 + Math.PI));
  pen.line(pt(hole, shoulder)).line(pt(hole + reach, slit)).line(pt(hole + gap, slit));
  const h0 = angle(H, pt(hole + gap, slit));
  pen.arc(H, breather, h0, sweep(h0, angle(H, pt(hole - gap, slit)), nAngle));
  pen.line(counterR);
  const c0 = angle(O, counterR);
  pen.arc(O, r, c0, sweep(c0, angle(O, counterL), c0 - Math.PI));
  pen.line(pt(hole - gap, -slit));
  const h1 = angle(H, pt(hole - gap, -slit));
  pen.arc(H, breather, h1, sweep(h1, angle(H, pt(hole + gap, -slit)), nAngle + Math.PI));
  pen.line(pt(hole + reach, -slit)).line(pt(hole, -shoulder)).close();
  return pen.toString();
}

const stem = 157, round = 55, base = R, xHeight = -235, ascender = -537;

function bar(x, top, bottom = base) {
  const pen = new Pen().move([x + round, top]).line([x + stem - round, top]);
  pen.arc([x + stem - round, top + round], round, -Math.PI / 2, 0).line([x + stem, bottom - round]);
  pen.arc([x + stem - round, bottom - round], round, 0, Math.PI / 2).line([x + round, bottom]);
  pen.arc([x + round, bottom - round], round, Math.PI / 2, Math.PI).line([x, top + round]);
  return pen.arc([x + round, top + round], round, Math.PI, Math.PI * 1.5).close().toString();
}

function u(x) {
  const right = x + 511, bowl = 245, inner = (511 - 2 * stem) / 2, floor = 186;
  const pen = new Pen().move([x + round, xHeight]).line([x + stem - round, xHeight]);
  pen.arc([x + stem - round, xHeight + round], round, -Math.PI / 2, 0).line([x + stem, floor - inner]);
  pen.arc([x + stem + inner, floor - inner], inner, Math.PI, 0).line([right - stem, xHeight + round]);
  pen.arc([right - stem + round, xHeight + round], round, Math.PI, Math.PI * 1.5).line([right - round, xHeight]);
  pen.arc([right - round, xHeight + round], round, -Math.PI / 2, 0).line([right, base - bowl]);
  pen.arc([right - bowl, base - bowl], bowl, 0, Math.PI / 2).line([x + bowl, base]);
  pen.arc([x + bowl, base - bowl], bowl, Math.PI / 2, Math.PI).line([x, xHeight + round]);
  return pen.arc([x + round, xHeight + round], round, Math.PI, Math.PI * 1.5).close().toString();
}

function dot(c, radius) {
  return new Pen().move([c[0] + radius, c[1]]).arc(c, radius, 0, Math.PI * 2).close().toString();
}

const moved = (path, scale, dx, dy) => path.replace(/(-?\d+(?:\.\d+)?) (-?\d+(?:\.\d+)?)/g,
  (_, x, y) => `${f(Number(x) * scale + dx)} ${f(base + (Number(y) - base) * scale + dy)}`);

const capital = 1.14, overshoot = 9, shift = -25;
export const aperture = mark();
export const q = moved(aperture, capital, 0, overshoot);
export const uill = moved([u(475), bar(1074, xHeight), dot([1074 + stem / 2, -399], 92), bar(1317, ascender), bar(1559, ascender)].join(' '), 1, shift, 0);
export const wordmark = `${q} ${uill}`;
export const svg = (path, ink) => `<path d="${path}" fill="${ink}" fill-rule="evenodd"/>`;
