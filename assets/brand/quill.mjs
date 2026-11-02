const f = (n) => Math.round(n * 10) / 10;
export const shape = {
  vane: [
    ['M', [0, -480]],
    ['C', [-22, -462], [-116, -360], [-128, -168]],
    ['L', [-58, -116]],
    ['L', [-127, -146]],
    ['C', [-124, -30], [-80, 76], [-11, 156]],
    ['L', [-9, 330]],
    ['L', [9, 330]],
    ['L', [11, 128]],
    ['C', [52, 92], [80, 18], [82, -74]],
    ['L', [38, -48]],
    ['L', [83, -92]],
    ['C', [86, -246], [30, -436], [0, -480]],
  ],
  rachis: [['M', [-4.2, 140]], ['L', [-0.6, -420]], ['L', [0.6, -420]], ['L', [4.2, 140]]],
  nib: [['M', [-9, 330]], ['L', [9, 330]], ['L', [5, 400]], ['L', [-1, 488]], ['C', [-5, 440], [-9, 380], [-9, 330]]],
};
const bend = 0.04, tilt = 42;
const raw = ([x, y]) => {
  const bx = x + (bend * y * y) / 400;
  const a = (tilt * Math.PI) / 180;
  return [bx * Math.cos(a) - y * Math.sin(a), bx * Math.sin(a) + y * Math.cos(a)];
};
const all = [...shape.vane, ...shape.nib].flatMap(([, ...p]) => p).map(raw);
const box = { x0: Math.min(...all.map((p) => p[0])), x1: Math.max(...all.map((p) => p[0])), y0: Math.min(...all.map((p) => p[1])), y1: Math.max(...all.map((p) => p[1])) };
export const center = [(box.x0 + box.x1) / 2, (box.y0 + box.y1) / 2];
export const size = Math.max(box.x1 - box.x0, box.y1 - box.y0);
export const transform = (cx, cy, s) => (p) => {
  const [x, y] = raw(p);
  return [cx + s * (x - center[0]), cy + s * (y - center[1])];
};
export const d = (cmds, T) => cmds.map(([c, ...pts]) => c + ' ' + pts.map((p) => T(p).map(f).join(' ')).join(' ')).join(' ') + ' Z';
export const svg = ({ ink, tip }, cx = 512, cy = 512, s = 1) => {
  const T = transform(cx, cy, s);
  return `<path d="${d(shape.vane, T)} ${d(shape.rachis, T)}" fill="${ink}" fill-rule="evenodd"/><path d="${d(shape.nib, T)}" fill="${tip}"/>`;
};
