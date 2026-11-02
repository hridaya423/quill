import { StateEffect, StateField, type Range } from '@codemirror/state';
import { Decoration, EditorView, ViewPlugin, type ViewUpdate } from '@codemirror/view';
import { local, place, post } from './bridge';

export type NoteSpec = { id: number; from: number; to: number; lens: string | null; note: string };
type Notes = { list: NoteSpec[]; active: number | null; busy: boolean };

export const setNotes = StateEffect.define<Notes>();

const field = StateField.define<Notes>({
  create: () => ({ list: [], active: null, busy: false }),
  update(value, tr) {
    for (const e of tr.effects) if (e.is(setNotes)) return e.value;
    if (!tr.docChanged) return value;
    return { ...value, list: value.list.map((n) => ({ ...n, from: tr.changes.mapPos(n.from, 1), to: tr.changes.mapPos(n.to, -1) })) };
  },
  provide: (f) => [
    EditorView.decorations.compute([f], (state) => {
      const { list, active } = state.field(f);
      const ranges: Range<Decoration>[] = list
        .filter((n) => n.to > n.from)
        .map((n) => Decoration.mark({ class: n.id === active ? 'cm-note cm-note-on' : 'cm-note' }).range(n.from, n.to));
      return Decoration.set(ranges, true);
    }),
    EditorView.editorAttributes.compute([f], (state) => ({ class: state.field(f).list.length ? 'cm-with-notes' : '' })),
  ],
});

function card(note: NoteSpec) {
  const el = document.createElement('div');
  el.className = 'cm-note-card';
  if (note.lens) {
    const lens = document.createElement('div');
    lens.className = 'cm-note-lens';
    lens.textContent = note.lens;
    el.appendChild(lens);
  }
  const body = document.createElement('div');
  body.className = 'cm-note-body';
  body.textContent = note.note;
  el.appendChild(body);
  const actions = document.createElement('div');
  actions.className = 'cm-note-actions';
  const apply = document.createElement('button');
  apply.className = 'cm-note-apply';
  apply.textContent = 'Apply';
  const dismiss = document.createElement('button');
  dismiss.textContent = 'Dismiss';
  for (const b of [apply, dismiss]) b.addEventListener('mousedown', (e) => e.preventDefault());
  apply.addEventListener('click', () => post({ type: 'applyNote', id: note.id }));
  dismiss.addEventListener('click', () => post({ type: 'dismissNote', id: note.id }));
  actions.append(apply, dismiss);
  el.appendChild(actions);
  el.addEventListener('mouseenter', () => post({ type: 'noteHover', id: note.id }));
  el.addEventListener('mouseleave', () => post({ type: 'noteHover', id: null }));
  return el;
}

const margin = ViewPlugin.fromClass(
  class {
    cards = new Map<number, HTMLElement>();

    constructor(readonly view: EditorView) {
      this.sync();
    }

    update(u: ViewUpdate) {
      if (u.startState.field(field) !== u.state.field(field)) this.sync();
      else if (this.cards.size && (u.geometryChanged || u.viewportChanged)) this.measure();
    }

    sync() {
      const { list, active, busy } = this.view.state.field(field);
      const wanted = new Set(list.map((n) => n.id));
      for (const [id, el] of this.cards) {
        if (!wanted.has(id)) {
          el.remove();
          this.cards.delete(id);
        }
      }
      for (const note of list) {
        let el = this.cards.get(note.id);
        if (!el) {
          el = card(note);
          this.view.scrollDOM.appendChild(el);
          this.cards.set(note.id, el);
        }
        el.classList.toggle('cm-note-card-on', note.id === active);
        const apply = el.querySelector<HTMLButtonElement>('.cm-note-apply')!;
        apply.disabled = busy;
        apply.title = busy ? 'Wait for the current request to finish' : 'Ask Quill to make this edit';
      }
      this.measure();
    }

    measure() {
      const { list } = this.view.state.field(field);
      this.view.requestMeasure({
        read: (view) => {
          const content = view.contentDOM.getBoundingClientRect();
          const pad = parseFloat(getComputedStyle(view.contentDOM).paddingRight) || 0;
          return {
            x: content.right - pad + 40,
            tops: list.map((n) => view.coordsAtPos(n.from, 1)?.top ?? null),
            heights: list.map((n) => this.cards.get(n.id)?.offsetHeight ?? 0),
          };
        },
        write: (m, view) => {
          let floor = -Infinity;
          list.forEach((n, i) => {
            const el = this.cards.get(n.id);
            const top = m.tops[i];
            if (!el || top === null) return;
            const at = local(view.scrollDOM, { left: m.x, top: top + 4 });
            const y = Math.max(at.top, floor);
            place(el, at.left, y);
            floor = y + m.heights[i] + 14;
          });
        },
      });
    }

    destroy() {
      for (const el of this.cards.values()) el.remove();
    }
  },
);

export const notes = [field, margin];
