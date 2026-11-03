import { ChangeSet, Compartment, EditorSelection, EditorState, StateEffect, Transaction } from '@codemirror/state';
import { EditorView, drawSelection, dropCursor, keymap } from '@codemirror/view';
import { defaultKeymap, history, indentWithTab, invertedEffects, isolateHistory, redo, undo } from '@codemirror/commands';
import { autocompletion, closeBrackets, closeBracketsKeymap, completionKeymap, type CompletionContext } from '@codemirror/autocomplete';
import { bracketMatching, foldGutter, foldKeymap, forceParsing, indentOnInput } from '@codemirror/language';
import { searchKeymap } from '@codemirror/search';
import { lintKeymap } from '@codemirror/lint';
import { markdown } from '@codemirror/lang-markdown';
import { GFM } from '@lezer/markdown';
import {
  blockQuoteExtension,
  bulletListExtension,
  clickLinkExtension,
  clickLinkHandler,
  codeBlockDecorationsExtension,
  dashExtension,
  defaultClickLinkHandler,
  defaultHideExtensions,
  emojiExtension,
  fixedTabWidthExtension,
  horizonalRuleExtension,
  prosemarkBaseThemeSetup,
  prosemarkMarkdownFormattingKeymap,
  prosemarkMarkdownSyntaxExtensions,
  revealBlockOnArrowExtension,
  softIndentExtension,
  taskExtension,
} from '@prosemark/core';
import { obsidian } from './syntax';
import { dispatchPinned } from './pin';
import { blocks, forgetEmbeds, startAfterProperties, nested, nestedBlocks, preload, reborn, refresh, reviewRanges, setEmbeds, track, type Payload } from './blocks';
import { ornaments } from './ornaments';
import { review, setHunks, setCard, pending, type HunkSpec, type CardSpec } from './review';
import { notes, setNotes, type NoteSpec } from './notes';
import { stage, presenceTracker, present, sweep, play, land, playing } from './stage';
import { post, step, type Edit, type Step } from './bridge';
import { heading, wrap } from './format';
import { outline } from './outline';

let generation = 0;
let version = 0;
let log: ChangeSet[] = [];
let titles: string[] = [];
let scrolling = 0;
let lastSteps: Step[] = [];
let waiting: Record<string, Payload> | null = null;

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
  const { range, yMargin } = view.scrollSnapshot().value;
  post({ type: 'scroll', generation, top: range.head, shift: yMargin });
}

function restore(top: number, shift: number) {
  const snapshot = view.scrollSnapshot() as StateEffect<object> & { type: { of: (value: object) => StateEffect<object> } };
  const Target = snapshot.value.constructor as new (...args: unknown[]) => object;
  return snapshot.type.of(new Target(EditorSelection.cursor(top), 'start', 'start', shift, 0, true));
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

const language = markdown({ extensions: [GFM, prosemarkMarkdownSyntaxExtensions, obsidian] });

const setup = [
  defaultHideExtensions,
  blockQuoteExtension,
  bulletListExtension,
  taskExtension,
  emojiExtension,
  horizonalRuleExtension,
  dashExtension,
  revealBlockOnArrowExtension,
  clickLinkExtension,
  defaultClickLinkHandler,
  fixedTabWidthExtension,
  softIndentExtension,
  codeBlockDecorationsExtension,
  dropCursor(),
  indentOnInput(),
  bracketMatching(),
  closeBrackets(),
  keymap.of([
    ...prosemarkMarkdownFormattingKeymap,
    ...closeBracketsKeymap,
    ...defaultKeymap,
    ...searchKeymap,
    ...foldKeymap,
    ...completionKeymap,
    ...lintKeymap,
    indentWithTab,
  ]),
  foldGutter(),
];

nested(() => [language, setup, nestedBlocks, ornaments(() => {}), prosemarkBaseThemeSetup(), EditorView.lineWrapping]);
reviewRanges((state) => pending(state));

const extensions = [
  language,
  setup,
  blocks,
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
  outline,
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
  dispatchTransactions: dispatchPinned,
  state: EditorState.create({ doc: '', extensions }),
});
track(view);

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
  load(text: string, gen: number, anchor = 0, top = 0, shift = 0) {
    land(view, false);
    view.contentDOM.style.removeProperty('--nudge');
    generation = gen;
    version = 0;
    log = [];
    forgetEmbeds();
    reborn();
    preload(text);
    view.setState(EditorState.create({ doc: text, extensions, selection: { anchor: Math.min(anchor, text.length) } }));
    if (waiting) view.dispatch({ effects: setEmbeds.of(waiting) });
    const start = anchor === 0 ? startAfterProperties(view.state) : null;
    if (start !== null) view.dispatch({ selection: { anchor: start } });
    view.dispatch({ effects: restore(Math.min(top, text.length), shift) });
    waiting = null;
    requestAnimationFrame(viewport);
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
  embeds(found: Record<string, Payload>, early = false) {
    if (early) {
      waiting = { ...(waiting ?? {}), ...found };
      return;
    }
    refresh(view, [setEmbeds.of(found)]);
  },
  editable(on: boolean) { view.dispatch({ effects: editable.reconfigure(EditorView.editable.of(on)) }); },
  undo() { land(view, true); travel(view, true); },
  redo() { land(view, true); travel(view, false); },
  wrap(marker: string) { wrap(view, marker); },
  heading(level: number) { heading(view, level); },
  focus() { view.focus(); },
  text() { return view.state.doc.toString(); },
  face(name: string) {
    document.documentElement.dataset.face = name;
    view.dispatch({ selection: view.state.selection });
  },
  audit() {
    forceParsing(view, view.state.doc.length, 10000);
    const patterns: [string, RegExp][] = [
      ['wikilink', /\[\[|\]\]/],
      ['callout', /\[![\w-]+\]/],
      ['highlight', /==/],
      ['comment', /%%/],
      ['math', /\$\$|(?<![\w\\$])\$[^\s$][^$\n]*?[^\s\\$]\$(?!\d)/],
      ['block id', /\s\^[A-Za-z0-9-]+\s*$/],
      ['footnote', /\[\^[^\]]+\]/],
      ['html', /<\/?[a-z][a-z0-9-]*(\s[^>]*)?\/?>/i],
      ['rule', /^\s*(---|\*\*\*|___)\s*$/],
      ['heading', /^#{1,6}\s/],
      ['emphasis', /\*\*|(?<![\w*])\*(?=\S)[^*]+\*(?![\w*])|~~/],
      ['link', /\]\(|\]\[/],
      ['quote', /^\s*>/],
      ['fence', /^\s*(```|~~~)/],
      ['image', /!\[/],
    ];
    const found = new Map<string, { kind: string; text: string }>();
    const s = view.scrollDOM;
    const wait = () => { (view as any).measure(); (view as any).measure(); };
    const caretLine = view.state.doc.lineAt(view.state.selection.main.head).number;
    const scan = () => {
      for (const line of Array.from(view.dom.querySelectorAll('.cm-line')) as HTMLElement[]) {
        if (line.closest('.cm-fenced-code-line') || line.classList.contains('cm-fenced-code-line')) continue;
        const nestedLine = !!line.closest('.cm-embed-body');
        let key = '';
        if (!nestedLine) {
          let n = 0;
          try { n = view.state.doc.lineAt(view.posAtDOM(line)).number; } catch { continue; }
          if (n === caretLine) continue;
          key = `L${n}`;
        } else {
          key = `E${line.textContent}`;
        }
        const clone = line.cloneNode(true) as HTMLElement;
        for (const el of Array.from(clone.querySelectorAll('.cm-hidden-token, .cm-transparent-token, .cm-inline-code, .cm-math, .cm-diagram, .cm-code-block-info, img, svg, .katex'))) el.remove();
        const text = clone.textContent ?? '';
        for (const [kind, re] of patterns) {
          if (re.test(text)) found.set(`${key}:${kind}`, { kind, text: text.slice(0, 160) });
        }
      }
    };
    s.scrollTop = 0;
    wait();
    for (let guard = 0; guard < 400; guard++) {
      scan();
      if (s.scrollTop + s.clientHeight >= s.scrollHeight - 2) break;
      s.scrollTop += s.clientHeight * 0.8;
      wait();
    }
    const errors = Array.from(view.dom.querySelectorAll('.cm-diagram-note, .cm-math-error')).map((e) => (e as HTMLElement).textContent || (e as HTMLElement).title).filter(Boolean);
    return JSON.stringify({ raw: [...found.entries()].map(([k, v]) => ({ at: k.split(':')[0], ...v })), errors });
  },
  bench(n = 300, at = view.state.selection.main.head) {
    const times: number[] = [];
    const start = at;
    const begin = performance.now();
    for (let i = 0; i < n; i++) {
      const t = performance.now();
      view.dispatch({ changes: { from: at, insert: i % 7 === 6 ? ' ' : 'a' }, selection: { anchor: at + 1 }, userEvent: 'input.type' });
      at += 1;
      view.contentDOM.getBoundingClientRect();
      times.push(performance.now() - t);
    }
    const mean = (performance.now() - begin) / n;
    view.dispatch({ changes: { from: start, to: at }, selection: { anchor: start } });
    times.sort((a, b) => a - b);
    return { mean: Math.round(mean * 1000) / 1000, p50: times[Math.floor(n / 2)], p95: times[Math.floor(n * 0.95)], max: times[n - 1] };
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
