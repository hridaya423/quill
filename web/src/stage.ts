import { ChangeSet, Prec, StateEffect, StateField, type Range } from '@codemirror/state';
import { Decoration, EditorView, ViewPlugin, WidgetType, type ViewUpdate } from '@codemirror/view';
import { local, post, still } from './bridge';

type Cut = { from: number; to: number };
type Typed = { from: number; to: number; shown: number };
type Scene = { cuts: Cut[]; lifting: boolean; typed: Typed[] };

const setScene = StateEffect.define<Scene | null>();

class Caret extends WidgetType {
  eq() { return true; }
  toDOM() {
    const el = document.createElement('span');
    el.className = 'cm-typing-caret';
    return el;
  }
}

const scene = StateField.define<Scene | null>({
  create: () => null,
  update(value, tr) {
    for (const e of tr.effects) if (e.is(setScene)) return e.value;
    if (!value || !tr.docChanged) return value;
    return {
      ...value,
      cuts: value.cuts.map((c) => ({ from: tr.changes.mapPos(c.from, 1), to: tr.changes.mapPos(c.to, -1) })),
      typed: value.typed.map((t) => ({ ...t, from: tr.changes.mapPos(t.from, -1), to: tr.changes.mapPos(t.to, 1) })),
    };
  },
  provide: (f) =>
    EditorView.decorations.compute([f], (state) => {
      const s = state.field(f);
      if (!s) return Decoration.none;
      const ranges: Range<Decoration>[] = [];
      const cut = Decoration.mark({ class: s.lifting ? 'cm-cut cm-lift' : 'cm-cut' });
      for (const c of s.cuts) if (c.to > c.from) ranges.push(cut.range(c.from, c.to));
      for (const [i, t] of s.typed.entries()) {
        const at = Math.min(t.to, t.from + t.shown);
        if (at < t.to) ranges.push(Decoration.mark({ class: 'cm-unrevealed' }).range(at, t.to));
        if (i < 8 && at < t.to) ranges.push(Decoration.widget({ widget: new Caret(), side: 1 }).range(at));
      }
      return Decoration.set(ranges, true);
    }),
});

let pending: { commit: () => void } | null = null;
let timer = 0;
let frame = 0;
let deadline = 0;
let busy = false;
let count = 0;

const wait = (ms: number) => new Promise<void>((done) => { timer = window.setTimeout(done, ms); });

function finish(view: EditorView) {
  clearTimeout(timer);
  clearTimeout(deadline);
  cancelAnimationFrame(frame);
  if (view.state.field(scene)) view.dispatch({ effects: setScene.of(null) });
  if (busy) {
    busy = false;
    post({ type: 'played', count });
  }
}

export function playing() {
  return busy;
}

export function land(view: EditorView, report: boolean) {
  if (!busy) return;
  pending?.commit();
  pending = null;
  if (report) finish(view);
  else {
    busy = false;
    clearTimeout(timer);
    clearTimeout(deadline);
    cancelAnimationFrame(frame);
  }
}

function visible(view: EditorView, pos: number) {
  const coords = view.coordsAtPos(pos);
  if (!coords) return false;
  const box = view.scrollDOM.getBoundingClientRect();
  return coords.top >= box.top + 96 && coords.bottom <= box.bottom - 96;
}

export async function play(view: EditorView, set: ChangeSet, token: number | null, commit: (set: ChangeSet, token: number | null) => void) {
  land(view, true);
  count = 0;
  set.iterChanges(() => { count += 1; });
  if (!count) return;
  busy = true;
  let committed = false;
  const run = () => {
    if (committed) return;
    committed = true;
    commit(set, token);
  };
  pending = { commit: run };
  if (still()) {
    run();
    pending = null;
    finish(view);
    return;
  }
  const cuts: Cut[] = [];
  let first = -1;
  set.iterChanges((fromA, toA) => {
    if (first < 0) first = fromA;
    if (toA > fromA) cuts.push({ from: fromA, to: toA });
  });
  if (!visible(view, first)) {
    const block = view.lineBlockAt(first);
    const box = view.scrollDOM;
    const top = Math.max(0, block.top + view.documentTop - box.getBoundingClientRect().top + box.scrollTop - box.clientHeight * 0.4);
    box.scrollTo({ top, behavior: 'smooth' });
    await wait(450);
    if (!busy || committed) return;
  }
  if (cuts.length) {
    view.dispatch({ effects: setScene.of({ cuts, lifting: false, typed: [] }) });
    await wait(240);
    if (!busy || committed) return;
    view.dispatch({ effects: setScene.of({ ...view.state.field(scene)!, lifting: true }) });
    await wait(300);
    if (!busy || committed) return;
  }
  const typed: Typed[] = [];
  set.iterChanges((_fromA, _toA, fromB, toB) => {
    if (toB > fromB) typed.push({ from: fromB, to: toB, shown: 0 });
  });
  view.dispatch({ effects: setScene.of(null) });
  run();
  pending = null;
  if (!typed.length) {
    await wait(120);
    if (busy) finish(view);
    return;
  }
  view.dispatch({ effects: setScene.of({ cuts: [], lifting: false, typed }) });
  const longest = Math.max(...typed.map((t) => t.to - t.from));
  const total = Math.min(800, Math.max(160, longest * 16));
  const start = performance.now();
  const tick = () => {
    if (!busy) return;
    const s = view.state.field(scene);
    if (!s) return finish(view);
    const t = Math.min(1, (performance.now() - start) / total);
    const next = s.typed.map((r) => ({ ...r, shown: Math.round((r.to - r.from) * t) }));
    view.dispatch({ effects: setScene.of({ ...s, typed: next }) });
    if (t < 1) frame = requestAnimationFrame(tick);
    else finish(view);
  };
  frame = requestAnimationFrame(tick);
  deadline = window.setTimeout(() => finish(view), total + 120);
}

let lastKey = 0;

export const stage = [
  scene,
  Prec.highest(
    EditorView.domEventHandlers({
      keydown(event, view) {
        const now = performance.now();
        const gap = now - lastKey;
        lastKey = now;
        if (!busy) return false;
        land(view, true);
        const bare = !event.metaKey && !event.altKey && !event.ctrlKey && !event.shiftKey;
        if (event.key === ' ' && bare && gap > 2000) {
          event.preventDefault();
          return true;
        }
        return false;
      },
      mousedown(_event, view) {
        land(view, true);
        return false;
      },
    }),
  ),
];

let presence: HTMLElement | null = null;
let presented: { from: number; to: number } | null = null;
let sweeping = 0;

function position(view: EditorView) {
  const el = presence;
  const r = presented;
  if (!el || !r) return;
  view.requestMeasure({
    read: (v) => {
      const a = v.coordsAtPos(r.from, 1) ?? v.coordsAtPos(r.from, -1);
      const b = v.coordsAtPos(Math.max(r.from, r.to - 1), -1) ?? a;
      const content = v.contentDOM.getBoundingClientRect();
      const pad = parseFloat(getComputedStyle(v.contentDOM).paddingLeft) || 0;
      return a && b ? { a, b, left: content.left + pad } : null;
    },
    write: (m, v) => {
      if (!m) return;
      const at = local(v.scrollDOM, { left: m.left - 35, top: m.a.top + 4 });
      el.style.transform = `translate(${Math.round(at.left)}px, ${Math.round(at.top)}px)`;
      el.style.height = `${Math.max(m.b.bottom - m.a.top - 8, 16)}px`;
    },
  });
}

export function present(view: EditorView, r: { from: number; to: number } | null, fromSweep = false) {
  if (!fromSweep) {
    clearInterval(sweeping);
    sweeping = 0;
  }
  presented = r;
  if (!r) {
    const el = presence;
    presence = null;
    if (el) {
      el.classList.remove('cm-presence-shown');
      setTimeout(() => el.remove(), 260);
    }
    return;
  }
  if (!presence) {
    presence = document.createElement('div');
    presence.className = 'cm-presence';
    view.scrollDOM.appendChild(presence);
    position(view);
    presence.getBoundingClientRect();
    presence.classList.add('cm-presence-shown');
    return;
  }
  position(view);
}

export function sweep(view: EditorView) {
  if (sweeping) return;
  const doc = view.state.doc;
  if (!doc.length) return;
  const box = view.scrollDOM.getBoundingClientRect();
  const paragraphs: { from: number; to: number }[] = [];
  for (const block of view.viewportLineBlocks) {
    const top = block.top + view.documentTop;
    if (top + block.height < box.top || top > box.bottom) continue;
    const line = doc.lineAt(block.from);
    if (line.text.trim()) paragraphs.push({ from: line.from, to: line.to });
  }
  if (!paragraphs.length) return;
  let i = 0;
  present(view, paragraphs[0]);
  if (still()) return;
  sweeping = window.setInterval(() => {
    i = (i + 1) % paragraphs.length;
    present(view, paragraphs[i], true);
  }, 900);
}

export const presenceTracker = ViewPlugin.fromClass(
  class {
    update(u: ViewUpdate) {
      if (presented && u.docChanged) presented = { from: u.changes.mapPos(presented.from, 1), to: u.changes.mapPos(presented.to, -1) };
      if (presence && (u.docChanged || u.geometryChanged)) position(u.view);
    }
  },
);
