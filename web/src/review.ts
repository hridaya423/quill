import { StateEffect, StateField, type Range } from '@codemirror/state';
import { Decoration, EditorView, ViewPlugin, type ViewUpdate } from '@codemirror/view';
import { local, place, post } from './bridge';

export type HunkSpec = { id: number; from: number; to: number; flagged: boolean };
export type CardSpec = { id: number; from: number; to: number; old: string; flags: string[]; by: string | null };
type Hunks = { list: HunkSpec[]; focused: number | null };

export const setHunks = StateEffect.define<Hunks>();
export const setCard = StateEffect.define<CardSpec | null>();

const arrived = new Map<number, number>();

const hunks = StateField.define<Hunks>({
  create: () => ({ list: [], focused: null }),
  update(value, tr) {
    for (const e of tr.effects) if (e.is(setHunks)) return e.value;
    if (!tr.docChanged) return value;
    return {
      focused: value.focused,
      list: value.list.map((h) => ({ ...h, from: tr.changes.mapPos(h.from, -1), to: tr.changes.mapPos(h.to, 1) })),
    };
  },
  provide: (field) =>
    EditorView.decorations.compute([field], (state) => {
      const { list, focused } = state.field(field);
      const now = performance.now();
      const ranges: Range<Decoration>[] = [];
      for (const h of list) {
        if (!arrived.has(h.id)) arrived.set(h.id, now);
        const on = h.id === focused;
        const fresh = now - arrived.get(h.id)! < 400;
        if (h.to > h.from) {
          const cls = ['cm-hunk', h.flagged ? 'cm-hunk-flagged' : '', on ? 'cm-hunk-on' : ''].join(' ');
          ranges.push(Decoration.mark({ class: cls, attributes: { 'data-hunk': String(h.id) } }).range(h.from, h.to));
        }
        const first = state.doc.lineAt(h.from).number;
        const last = state.doc.lineAt(Math.max(h.from, h.to - 1)).number;
        for (let n = first; n <= last; n++) {
          const line = state.doc.line(n);
          if (line.length === 0 && n !== first) continue;
          const cls = ['cm-hunk-line', on ? 'cm-hunk-line-on' : '', fresh ? 'cm-hunk-line-fresh' : ''].join(' ');
          ranges.push(Decoration.line({ class: cls }).range(line.from));
        }
      }
      return Decoration.set(ranges, true);
    }),
});

export function pending(state: import('@codemirror/state').EditorState) {
  return state.field(hunks, false)?.list ?? [];
}

const card = StateField.define<CardSpec | null>({
  create: () => null,
  update(value, tr) {
    for (const e of tr.effects) if (e.is(setCard)) return e.value;
    if (!value || !tr.docChanged) return value;
    return { ...value, from: tr.changes.mapPos(value.from, -1), to: tr.changes.mapPos(value.to, 1) };
  },
});

function text(el: HTMLElement, tag: string, cls: string, content: string) {
  const node = document.createElement(tag);
  node.className = cls;
  node.textContent = content;
  el.appendChild(node);
  return node;
}

function button(label: string, title: string, run: () => void) {
  const b = document.createElement('button');
  b.textContent = label;
  b.title = title;
  b.addEventListener('mousedown', (e) => e.preventDefault());
  b.addEventListener('click', run);
  return b;
}

const gloss = ViewPlugin.fromClass(
  class {
    el: HTMLElement | null = null;
    shown: number | null = null;

    constructor(readonly view: EditorView) {
      this.sync();
    }

    update(u: ViewUpdate) {
      if (u.startState.field(card) !== u.state.field(card)) this.sync();
      else if (this.el && (u.geometryChanged || u.viewportChanged || u.docChanged)) this.measure();
    }

    sync() {
      const spec = this.view.state.field(card);
      if (!spec) {
        this.el?.remove();
        this.el = null;
        this.shown = null;
        return;
      }
      if (this.shown !== spec.id || !this.el) {
        this.el?.remove();
        const el = document.createElement('div');
        el.className = 'cm-gloss';
        el.setAttribute('role', 'group');
        el.setAttribute('aria-label', spec.old ? `Replaced: ${spec.old}` : 'Added text');
        if (spec.by) text(el, 'div', 'cm-gloss-by', spec.by);
        if (spec.old) text(el, 'div', 'cm-gloss-old', spec.old);
        else text(el, 'div', 'cm-gloss-added', 'Added');
        for (const flag of spec.flags) text(el, 'div', 'cm-gloss-flag', flag);
        const actions = document.createElement('div');
        actions.className = 'cm-gloss-actions';
        actions.append(
          button('Keep', 'Keep this change (⌘↩)', () => post({ type: 'keep', id: spec.id })),
          button('Revert', 'Put the old words back (⌘⌫)', () => post({ type: 'revert', id: spec.id })),
        );
        el.appendChild(actions);
        el.addEventListener('mouseenter', () => post({ type: 'cardHover', on: true }));
        el.addEventListener('mouseleave', () => post({ type: 'cardHover', on: false }));
        this.view.scrollDOM.appendChild(el);
        this.el = el;
        this.shown = spec.id;
        el.getBoundingClientRect();
        el.classList.add('cm-gloss-shown');
      }
      this.measure();
    }

    measure() {
      const spec = this.view.state.field(card);
      const el = this.el;
      if (!spec || !el) return;
      this.view.requestMeasure({
        read: (view) => {
          const start = view.coordsAtPos(spec.from, 1) ?? view.coordsAtPos(spec.from, -1);
          const end = view.coordsAtPos(Math.max(spec.from, spec.to), -1) ?? start;
          if (!start || !end) return null;
          const content = view.contentDOM.getBoundingClientRect();
          const pad = parseFloat(getComputedStyle(view.contentDOM).paddingRight) || 0;
          const scroller = view.scrollDOM.getBoundingClientRect();
          const columnRight = content.right - pad;
          const room = scroller.right - columnRight - 44;
          const textLeft = content.left + (parseFloat(getComputedStyle(view.contentDOM).paddingLeft) || 0);
          return { start, end, room, columnRight, textLeft, scrollerWidth: scroller.width, scroller: scroller.left };
        },
        write: (m, view) => {
          if (!m) return;
          const side = m.room >= 150;
          el.classList.toggle('cm-gloss-boxed', !side);
          el.style.width = side ? `${Math.min(220, m.room)}px` : '300px';
          if (side) {
            const at = local(view.scrollDOM, { left: m.columnRight + 24, top: m.start.top + 3 });
            place(el, at.left, at.top);
          } else {
            const width = 300;
            const left = Math.min(Math.max(m.textLeft, m.start.left - 20), m.scroller + m.scrollerWidth - width - 12);
            const at = local(view.scrollDOM, { left, top: m.end.bottom + 8 });
            place(el, at.left, at.top);
          }
        },
      });
    }

    destroy() {
      this.el?.remove();
    }
  },
);

let hovered: number | null = null;

const hover = EditorView.domEventHandlers({
  mousemove(event, view) {
    const pos = view.posAtCoords({ x: event.clientX, y: event.clientY });
    const list = view.state.field(hunks).list;
    const hit = pos === null ? null : list.find((h) => pos >= h.from && pos <= Math.max(h.to, h.from + 1) && (h.to > h.from || view.state.doc.lineAt(h.from).number === view.state.doc.lineAt(pos).number));
    const id = hit?.id ?? null;
    if (id !== hovered) {
      hovered = id;
      post({ type: 'hover', id });
    }
    return false;
  },
  mouseleave() {
    if (hovered !== null) {
      hovered = null;
      post({ type: 'hover', id: null });
    }
    return false;
  },
});

export const review = [hunks, card, gloss, hover];
