export function spline(points, n = 600) {
  const out = [];
  const p = [points[0], ...points, points[points.length - 1]];
  const per = n / (points.length - 1);
  for (let i = 1; i < p.length - 2; i++) {
    for (let k = 0; k < per; k++) {
      const t = k / per;
      const [p0, p1, p2, p3] = [p[i - 1], p[i], p[i + 1], p[i + 2]];
      const f = (a, b, c, d) => 0.5 * (2 * b + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t * t + (-a + 3 * b - 3 * c + d) * t * t * t);
      out.push([f(p0[0], p1[0], p2[0], p3[0]), f(p0[1], p1[1], p2[1], p3[1])]);
    }
  }
  out.push(points[points.length - 1]);
  const lengths = [0];
  for (let i = 1; i < out.length; i++) lengths.push(lengths[i - 1] + Math.hypot(out[i][0] - out[i - 1][0], out[i][1] - out[i - 1][1]));
  const total = lengths[lengths.length - 1];
  return (t) => {
    const target = t * total;
    let i = lengths.findIndex((l) => l >= target);
    if (i <= 0) i = 1;
    const a = out[i - 1], b = out[i];
    const f = (target - lengths[i - 1]) / Math.max(1e-6, lengths[i] - lengths[i - 1]);
    const dx = b[0] - a[0], dy = b[1] - a[1], d = Math.hypot(dx, dy) || 1;
    return { x: a[0] + dx * f, y: a[1] + dy * f, tx: dx / d, ty: dy / d };
  };
}

function mix(stops, t) {
  t = Math.min(1, Math.max(0, t));
  for (let i = 1; i < stops.length; i++) {
    if (t <= stops[i][0]) {
      const [t0, c0] = stops[i - 1], [t1, c1] = stops[i];
      const f = (t - t0) / (t1 - t0);
      return c0.map((v, k) => Math.round(v + (c1[k] - v) * f));
    }
  }
  return stops[stops.length - 1][1];
}

const hex = (s) => [1, 3, 5].map((i) => parseInt(s.slice(i, i + 2), 16));

function random(seed) {
  return () => {
    seed = (seed * 1664525 + 1013904223) % 4294967296;
    return seed / 4294967296;
  };
}

const round = (v) => Math.round(v * 10) / 10;

export function barbs(path, o) {
  const { width, inner, barbs: count, angle, curl, splits, colors, alpha, jitter = 0, seed = 7, vane, shaftWidth, nib, stroke, shaftOpacity } = o;
  const stops = colors.map(([t, c]) => [t, hex(c)]);
  const rand = random(seed);
  const envelope = (t) => {
    const rise = Math.min(1, t / 0.2);
    const fall = t < 0.45 ? 1 : 1 - ((t - 0.45) / (vane - 0.45)) * 0.55;
    return Math.sin((rise * Math.PI) / 2) ** 0.8 * fall;
  };
  const list = [];
  for (const side of [1, -1]) {
    const scale = (side === 1 ? 1 : inner) * width;
    for (let i = 0; i < count; i++) {
      const t = 0.008 + (i / count) * (vane - 0.008);
      let gap = false, kink = 0;
      for (const [s, sd] of splits) {
        if (sd !== side) continue;
        const d = t - s;
        if (Math.abs(d) < 0.006) gap = true;
        else if (d > 0 && d < 0.06) kink = (1 - d / 0.06) * 0.35;
      }
      if (gap) continue;
      const p = path(t);
      const nx = -p.ty * side, ny = p.tx * side;
      const a = angle + kink + (rand() - 0.5) * jitter * 0.12;
      const len = scale * envelope((t / vane) * 0.82) * (1 - kink * 0.35) * (1 + (rand() - 0.5) * jitter * 0.16);
      const op = alpha * (1 - rand() * jitter * 0.3);
      if (len < 2) continue;
      const dx = nx * Math.cos(a) - p.tx * Math.sin(a), dy = ny * Math.cos(a) - p.ty * Math.sin(a);
      const [r, g, b] = mix(stops, t / vane);
      list.push([round(t / vane), round(p.x), round(p.y), round(p.x + dx * len * 0.5 - p.tx * len * curl), round(p.y + dy * len * 0.5 - p.ty * len * curl),
        round(p.x + dx * len), round(p.y + dy * len), r, g, b, Math.round(op * 100) / 100]);
    }
  }
  list.sort((a, b) => a[0] - b[0]);
  const left = [], right = [];
  for (let i = 0; i <= 160; i++) {
    const t = i / 160;
    const p = path(t);
    const u = (t - vane) / (1 - vane);
    const w = t < vane ? shaftWidth * (0.25 + 0.75 * (t / vane)) : shaftWidth * (1 + (nib - 1) * Math.sin(Math.PI * Math.min(1, u * 1.4)) ** 0.7) * (1 - u) ** 0.75 + 0.5;
    left.push([round(p.x - (p.ty * w) / 2), round(p.y + (p.tx * w) / 2)]);
    right.push([round(p.x + (p.ty * w) / 2), round(p.y - (p.tx * w) / 2)]);
  }
  return { stroke, vane, shaftOpacity, barbs: list, shaft: [...left, ...right.reverse()] };
}

export function feather(path, o) {
  const data = barbs(path, o);
  const lines = data.barbs.map(([, x0, y0, cx, cy, x1, y1, r, g, b, op]) =>
    `<path d="M${x0} ${y0} Q${cx} ${cy} ${x1} ${y1}" stroke="rgb(${r},${g},${b})" stroke-opacity="${op}" stroke-width="${data.stroke}" stroke-linecap="round" fill="none"/>`);
  const outline = data.shaft.map(([x, y], i) => `${i ? 'L' : 'M'}${x} ${y}`).join(' ') + 'Z';
  lines.push(`<path d="${outline}" fill="${o.shaft ?? '#FFF4E6'}" fill-opacity="${data.shaftOpacity}"/>`);
  return lines.join('\n');
}
