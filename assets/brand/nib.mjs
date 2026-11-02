const cubic = (p0, p1, p2, p3) => (t) => {
  const u = 1 - t;
  return [u*u*u*p0[0] + 3*u*u*t*p1[0] + 3*u*t*t*p2[0] + t*t*t*p3[0], u*u*u*p0[1] + 3*u*u*t*p1[1] + 3*u*t*t*p2[1] + t*t*t*p3[1]];
};

export function oval({ cx, cy, rx, ry, tilt, from, sweep }, n = 900) {
  const c = Math.cos(tilt), s = Math.sin(tilt);
  return Array.from({ length: n + 1 }, (_, i) => {
    const a = from + (sweep * i) / n;
    const x = rx * Math.cos(a), y = ry * Math.sin(a);
    return [cx + x * c - y * s, cy + x * s + y * c];
  });
}

export function curve(p0, p1, p2, p3, n = 400) {
  const b = cubic(p0, p1, p2, p3);
  return Array.from({ length: n + 1 }, (_, i) => b(i / n));
}

const r = (v) => Math.round(v * 10) / 10;

export function ribbon(pts, { nib, angle, pressure }, part = [0, 1]) {
  const hx = Math.cos(angle) / 2, hy = -Math.sin(angle) / 2;
  const lens = [0];
  for (let i = 1; i < pts.length; i++) lens.push(lens[i - 1] + Math.hypot(pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1]));
  const total = lens[lens.length - 1];
  const a = [], b = [];
  pts.forEach((p, i) => {
    const u = lens[i] / total;
    if (u < part[0] || u > part[1]) return;
    const w = nib * pressure(u);
    a.push([r(p[0] + hx * w), r(p[1] + hy * w)]);
    b.push([r(p[0] - hx * w), r(p[1] - hy * w)]);
  });
  return [...a, ...b.reverse()].map(([x, y], i) => `${i ? 'L' : 'M'}${x} ${y}`).join('') + 'Z';
}

export function hairline({ rx, ry, tilt }, angle, near) {
  const nx = Math.cos(angle), ny = -Math.sin(angle);
  const c = Math.cos(tilt), s = Math.sin(tilt);
  const cross = (a) => {
    const tx = -rx * Math.sin(a), ty = ry * Math.cos(a);
    return (tx * c - ty * s) * ny - (tx * s + ty * c) * nx;
  };
  let lo = near - 0.6, hi = near + 0.6;
  for (let i = 0; i < 80; i++) {
    const mid = (lo + hi) / 2;
    if (Math.sign(cross(lo)) === Math.sign(cross(mid))) lo = mid; else hi = mid;
  }
  return (lo + hi) / 2;
}
