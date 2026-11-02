import { ChangeSet, Compartment, EditorState, StateEffect, Transaction } from '@codemirror/state';
import { EditorView, drawSelection, keymap } from '@codemirror/view';
import { history, invertedEffects, isolateHistory, redo, undo } from '@codemirror/commands';
import { autocompletion, type CompletionContext } from '@codemirror/autocomplete';
import { markdown } from '@codemirror/lang-markdown';
import { GFM } from '@lezer/markdown';
import {
  clickLinkHandler,
  prosemarkBasicSetup,
  prosemarkBaseThemeSetup,
  prosemarkMarkdownSyntaxExtensions,
} from '@prosemark/core';
import { ornaments } from './ornaments';
import { review, setHunks, setCard, type HunkSpec, type CardSpec } from './review';
import { notes, setNotes, type NoteSpec } from './notes';
import { stage, presenceTracker, present, sweep, play, land, playing } from './stage';
import { post, step, type Edit, type Step } from './bridge';
import { heading, wrap } from './format';

let generation = 0;
let version = 0;
let log: ChangeSet[] = [];
let titles: string[] = [];
let scrolling = 0;
let lastSteps: Step[] = [];

function mapped(edits: Edit[], base: number): ChangeSet {
  const length = base < log.length ? log[base].length : view.state.doc.length;
  let set = ChangeSet.of(edits.map(([from, to, insert]) => ({ from, to, insert })), length);
  for (const cs of log.slice(base)) set = set.map(cs);
  return set;
}

function mapPos(pos: number, base: number, assoc = 1) {
  for (const cs of log.slice(base)) pos = cs.mapPos(pos, assoc);
  return Math.min(pos, view.state.doc.length);
}

const bridge = EditorView.updateListener.of((u) => {
  const { anchor, head } = u.state.selection.main;
  const steps: Step[] = [];
  let kind = 'do';
  for (const tr of u.transactions) {
    if (tr.isUserEvent('undo')) kind = 'undo';
    if (tr.isUserEvent('redo')) kind = 'redo';
    for (const e of tr.effects) if (e.is(step)) steps.push(e.value);
  }
  lastSteps = steps;
  if (u.docChanged) {
    log.push(u.changes);
    version += 1;
    const changes: Edit[] = [];
    u.changes.iterChanges((fromA, toA, _fromB, _toB, inserted) => changes.push([fromA, toA, inserted.toString()]));
    post({ type: 'change', generation, version, changes, steps, kind, anchor, head });
  } else if (steps.length) {
    post({ type: 'change', generation, version, changes: [], steps, kind, anchor, head });
  } else if (u.selectionSet) {
    post({ type: 'select', generation, anchor, head });
  }
});

function viewport() {
  const s = view.scrollDOM;
  const rect = s.getBoundingClientRect();
  const anchor = view.posAtCoords({ x: rect.left + rect.width / 2, y: rect.top + rect.height * 0.25 }, false);
  post({ type: 'scroll', generation, top: s.scrollTop, anchor, atEnd: s.scrollTop + s.clientHeight >= s.scrollHeight - 4 });
}

const editable = new Compartment();

function complete(context: CompletionContext) {
  const before = context.matchBefore(/\[\[[^\[\]\n|]*/);
  if (!before) return null;
  const query = before.text.slice(2).toLowerCase();
  const closing = context.state.sliceDoc(context.pos, context.pos + 2) === ']]';
  return {
    from: before.from + 2,
    options: titles
      .filter((t) => t.toLowerCase().includes(query))
      .map((t) => ({ label: t, apply: closing ? t : `${t}]]` })),
    validFor: /^[^\[\]\n|]*$/,
  };
}

const extensions = [
  markdown({ extensions: [GFM, prosemarkMarkdownSyntaxExtensions] }),
  prosemarkBasicSetup({ history: false }),
  history(),
  invertedEffects.of((tr) =>
    tr.effects.filter((e) => e.is(step)).map((e) => step.of({ ...e.value, dir: e.value.dir === 1 ? -1 : 1 })),
  ),
  keymap.of([
    { key: 'Mod-z', run: (v) => travel(v, true), preventDefault: true },
    { key: 'Mod-Shift-z', run: (v) => travel(v, false), preventDefault: true },
  ]),
  prosemarkBaseThemeSetup(),
  clickLinkHandler.of((url) => post({ type: 'link', url })),
  ornaments((title) => post({ type: 'note', title })),
  autocompletion({ override: [complete], icons: false }),
  review,
  notes,
  stage,
  presenceTracker,
  drawSelection(),
  editable.of(EditorView.editable.of(true)),
  EditorView.lineWrapping,
  EditorView.contentAttributes.of({ spellcheck: 'true', autocorrect: 'on', autocapitalize: 'on' }),
  EditorView.domEventHandlers({
    scroll() {
      if (scrolling) return;
      scrolling = requestAnimationFrame(() => {
        scrolling = 0;
        viewport();
      });
    },
  }),
  EditorView.exceptionSink.of((e) => post({ type: 'error', message: String(e?.stack ?? e) })),
  bridge,
];

const view = new EditorView({
  parent: document.getElementById('page')!,
  state: EditorState.create({ doc: '', extensions }),
});

let group: number | undefined;

function travel(v: EditorView, back: boolean) {
  const go = back ? undo : redo;
  const undoBack = back ? redo : undo;
  lastSteps = [];
  if (!go(v)) return false;
  const turn = lastSteps.find((s) => s.group !== undefined)?.group;
  if (turn === undefined) return true;
  for (;;) {
    lastSteps = [];
    if (!go(v)) break;
    if (lastSteps.find((s) => s.group !== undefined)?.group !== turn) {
      undoBack(v);
      break;
    }
  }
  return true;
}

export function commitEdits(set: ChangeSet, token: number | null) {
  view.dispatch({
    changes: set,
    effects: token === null ? [] : [step.of({ token, dir: 1, group })],
    annotations: [Transaction.userEvent.of(token === null ? 'quill.other' : 'quill.agent'), isolateHistory.of('full')],
  });
}

const quill = {
  view,
  load(text: string, gen: number, anchor = 0, top = 0) {
    land(view, false);
    generation = gen;
    version = 0;
    log = [];
    view.setState(EditorState.create({ doc: text, extensions, selection: { anchor: Math.min(anchor, text.length) } }));
    requestAnimationFrame(() => {
      view.scrollDOM.scrollTop = top;
      viewport();
    });
  },
  apply(edits: Edit[], base: number, token: number | null) {
    land(view, true);
    group = undefined;
    commitEdits(mapped(edits, base), token);
  },
  mark(token: number) {
    land(view, true);
    view.dispatch({ effects: step.of({ token, dir: 1 }), annotations: isolateHistory.of('full') });
  },
  select(anchor: number, head: number, base: number) {
    view.dispatch({ selection: { anchor: mapPos(anchor, base), head: mapPos(head, base) } });
  },
  reveal(pos: number, base: number) {
    view.dispatch({ effects: EditorView.scrollIntoView(mapPos(pos, base), { y: 'nearest', yMargin: 96 }) });
  },
  glide(pos: number, base: number) {
    const block = view.lineBlockAt(mapPos(pos, base));
    const top = Math.max(0, block.top + view.documentTop - view.scrollDOM.getBoundingClientRect().top + view.scrollDOM.scrollTop - 64);
    const still = matchMedia('(prefers-reduced-motion: reduce)').matches;
    view.scrollDOM.scrollTo({ top, behavior: still ? 'auto' : 'smooth' });
  },
  hunks(list: HunkSpec[], focused: number | null, base: number) {
    view.dispatch({ effects: setHunks.of({ list: list.map((h) => ({ ...h, from: mapPos(h.from, base, -1), to: mapPos(h.to, base) })), focused }) });
  },
  card(spec: CardSpec | null, base: number) {
    view.dispatch({ effects: setCard.of(spec && { ...spec, from: mapPos(spec.from, base, -1), to: mapPos(spec.to, base) }) });
  },
  notes(list: NoteSpec[], active: number | null, busy: boolean, base: number) {
    view.dispatch({ effects: setNotes.of({ list: list.map((n) => ({ ...n, from: mapPos(n.from, base, -1), to: mapPos(n.to, base) })), active, busy }) });
  },
  present(from: number | null, to: number, base: number) {
    present(view, from === null ? null : { from: mapPos(from, base), to: mapPos(to, base) });
  },
  sweep() { sweep(view); },
  play(edits: Edit[], base: number, token: number | null, turn: number | null) {
    play(view, mapped(edits, base), token, (set, t) => {
      group = turn ?? undefined;
      commitEdits(set, t);
      group = undefined;
    });
  },
  land() { land(view, true); },
  playing() { return playing(); },
  titles(list: string[]) { titles = list; },
  editable(on: boolean) { view.dispatch({ effects: editable.reconfigure(EditorView.editable.of(on)) }); },
  undo() { land(view, true); travel(view, true); },
  redo() { land(view, true); travel(view, false); },
  wrap(marker: string) { wrap(view, marker); },
  heading(level: number) { heading(view, level); },
  focus() { view.focus(); },
  text() { return view.state.doc.toString(); },
  face(name: string) { document.documentElement.dataset.face = name; },
  bench(n = 300) {
    const times: number[] = [];
    let at = view.state.doc.length;
    for (let i = 0; i < n; i++) {
      const t = performance.now();
      view.dispatch({ changes: { from: at, insert: i % 7 === 6 ? ' ' : 'a' }, selection: { anchor: at + 1 } });
      at += 1;
      view.contentDOM.getBoundingClientRect();
      times.push(performance.now() - t);
    }
    times.sort((a, b) => a - b);
    return { p50: times[Math.floor(n / 2)], p95: times[Math.floor(n * 0.95)], max: times[n - 1] };
  },
};

(window as any).quill = quill;
const warn = console.warn.bind(console);
console.warn = (...args: unknown[]) => {
  post({ type: 'error', message: args.map(String).join(' ') });
  warn(...args);
};
window.addEventListener('error', (e) => post({ type: 'error', message: String(e.error?.stack ?? e.message) }));
post({ type: 'ready' });
