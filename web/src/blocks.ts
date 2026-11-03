import { syntaxTree } from '@codemirror/language';
import { EditorSelection, EditorState, Facet, RangeSet, RangeValue, StateEffect, StateField, type Extension, type Range } from '@codemirror/state';
import { Decoration, EditorView, ViewPlugin, WidgetType, type DecorationSet, type ViewUpdate } from '@codemirror/view';
import type { SyntaxNode, SyntaxNodeRef } from '@lezer/common';
import { foldableSyntaxFacet } from '@prosemark/core';
import { parser as yaml } from '@lezer/yaml';
import { post } from './bridge';
import { rebuilds } from './incremental';
import { library, need, onLoaded, type Library, type PeleResult } from './lazy';

type Fold = {
  nodePath: string;
  keepDecorationOnUnfold?: boolean;
  buildDecorations: (state: EditorState, node: SyntaxNodeRef, touching: boolean) => Range<Decoration> | readonly Range<Decoration>[] | null | undefined | void;
};

const fold = (spec: Fold) => spec;

function folds(specs: readonly Fold[]) {
  const table = new Map<string, Fold[]>();
  for (const spec of specs) table.set(spec.nodePath, [...(table.get(spec.nodePath) ?? []), spec]);
  const lengths = new Set([...table.keys()].map((name) => name.length));
  return foldableSyntaxFacet.of({
    nodePath: (path: string) => {
      const at = path.lastIndexOf('/') + 1;
      return lengths.has(path.length - at) && table.has(path.slice(at));
    },
    keepDecorationOnUnfold: true,
    buildDecorations(state: EditorState, node: SyntaxNodeRef, touching: boolean) {
      const out: Range<Decoration>[] = [];
      for (const spec of table.get(node.name)!) {
        if (!spec.keepDecorationOnUnfold && touching) continue;
        const res = spec.buildDecorations(state, node, touching);
        if (Array.isArray(res)) out.push(...res);
        else if (res) out.push(res as Range<Decoration>);
      }
      return out;
    },
  });
}

function visible(specs: readonly Fold[]) {
  const table = new Map(specs.map((spec) => [spec.nodePath, spec]));
  const build = (view: EditorView) => {
    const { state } = view;
    const out: Range<Decoration>[] = [];
    for (const { from, to } of view.visibleRanges) {
      syntaxTree(state).iterate({
        from,
        to,
        enter(node) {
          const spec = table.get(node.name);
          if (!spec) return;
          const touching = state.selection.ranges.some((r) => r.from <= node.to && node.from <= r.to);
          if (!spec.keepDecorationOnUnfold && touching) return;
          const res = spec.buildDecorations(state, node, touching);
          if (Array.isArray(res)) out.push(...res);
          else if (res) out.push(res as Range<Decoration>);
        },
      });
    }
    return Decoration.set(out, true);
  };
  return ViewPlugin.fromClass(
    class {
      decorations: DecorationSet;
      constructor(view: EditorView) { this.decorations = build(view); }
      update(u: ViewUpdate) {
        if (u.docChanged || u.viewportChanged || u.selectionSet || syntaxTree(u.state) !== syntaxTree(u.startState)) this.decorations = build(u.view);
      }
    },
    { decorations: (v) => v.decorations },
  );
}

export type Payload =
  | { kind: 'note'; title: string; text: string; path: string; embeds?: Record<string, Payload> }
  | { kind: 'image'; url: string; width?: number; height?: number }
  | { kind: 'media'; url: string; media: 'video' | 'audio' }
  | { kind: 'file'; url: string; name: string }
  | { kind: 'missing'; title: string }
  | { kind: 'link'; title: string };

export const depth = Facet.define<number, number>({ combine: (v) => (v.length ? Math.max(...v) : 0) });
export const setEmbeds = StateEffect.define<Record<string, Payload>>();
const refreshed = StateEffect.define<null>();
const toggled = StateEffect.define<number>();
const drew = StateEffect.define<{ from: number; source: string }>();

const embedded = StateField.define<ReadonlyMap<string, Payload>>({
  create: () => new Map(),
  update(value, tr) {
    let next = value;
    for (const e of tr.effects) if (e.is(setEmbeds)) next = new Map([...next, ...Object.entries(e.value)]);
    return next;
  },
});

class Good extends RangeValue {
  constructor(readonly source: string) { super(); }
  eq(other: Good) { return other.source === this.source; }
}

const drawn = StateField.define<RangeSet<Good>>({
  create: () => RangeSet.empty,
  update(value, tr) {
    value = value.map(tr.changes);
    for (const e of tr.effects) {
      if (!e.is(drew)) continue;
      const { from, source } = e.value;
      value = value.update({ filter: (f) => f !== from, add: [new Good(source).range(from)] });
    }
    return value;
  },
});

class Open extends RangeValue {}

const opened = StateField.define<RangeSet<Open>>({
  create: () => RangeSet.empty,
  update(value, tr) {
    value = value.map(tr.changes);
    for (const e of tr.effects) {
      if (!e.is(toggled)) continue;
      let had = false;
      value.between(e.value, e.value, (from) => { if (from === e.value) had = true; });
      value = had ? value.update({ filter: (f) => f !== e.value }) : value.update({ add: [new Open().range(e.value)] });
    }
    return value;
  },
});

function good(state: EditorState, from: number) {
  let found: string | null = null;
  state.field(drawn).between(from, from, (f, _t, v) => {
    if (f === from) found = v.source;
  });
  return found as string | null;
}

export function refresh(view: EditorView, effects: StateEffect<unknown>[] = []) {
  view.dispatch({ selection: view.state.selection, effects: [refreshed.of(null), ...effects] });
}

let born = performance.now();
export function reborn() {
  born = performance.now();
}

const views = new Set<EditorView>();
onLoaded(() => {
  for (const v of views) if (v.dom.isConnected) refresh(v);
});

export function track(view: EditorView) {
  views.add(view);
}

const measured = new Map<string, number>();

function remember(view: EditorView, el: HTMLElement, key: string) {
  view.requestMeasure({
    read: () => (el.isConnected ? el.getBoundingClientRect().height : 0),
    write: (h) => {
      if (h > 0) measured.set(key, h);
      if (measured.size > 400) measured.delete(measured.keys().next().value!);
    },
  });
}

function hash(s: string) {
  let h = 2166136261;
  for (let i = 0; i < s.length; i++) h = Math.imul(h ^ s.charCodeAt(i), 16777619);
  return (h >>> 0).toString(36);
}

const sans = '-apple-system, system-ui, sans-serif';

type Drawing = { ok: true; result: PeleResult } | { ok: false; message: string };
const drawings = new Map<string, Drawing>();
const seen = new Set<string>();

function draw(source: string): Drawing | null {
  const pele = library('pele');
  if (!pele) return null;
  let d = drawings.get(source);
  if (d) {
    drawings.delete(source);
    drawings.set(source, d);
    return d;
  }
  try {
    d = { ok: true, result: pele.render(source, { fontFamily: sans, idPrefix: `d${hash(source)}-`, images: false }) };
  } catch (e: any) {
    const where = e?.line ? `Line ${e.line}: ` : '';
    const first = String(e?.message ?? e).split('\n')[0];
    d = { ok: false, message: where + first };
  }
  drawings.set(source, d);
  if (drawings.size > 96) drawings.delete(drawings.keys().next().value!);
  return d;
}

function column(view: EditorView) {
  const style = getComputedStyle(view.contentDOM);
  return view.contentDOM.clientWidth - parseFloat(style.paddingLeft) - parseFloat(style.paddingRight);
}

function fit(view: EditorView, r: PeleResult) {
  const room = Math.max(240, column(view) || 620);
  const scale = Math.min(1, room / r.width);
  const width = scale < 0.6 ? r.width * 0.6 : r.width * scale;
  return { width, height: r.height * (width / r.width), scrolls: scale < 0.6 };
}

function blockAt(view: EditorView, el: HTMLElement) {
  const pos = view.posAtDOM(el);
  let node: SyntaxNode | null = syntaxTree(view.state).resolveInner(pos, 1);
  while (node && node.name !== 'FencedCode' && node.name !== 'Math' && node.name !== 'Frontmatter' && node.name !== 'Document') node = node.parent;
  return node && node.name !== 'Document' ? node : null;
}

class Diagram extends WidgetType {
  constructor(readonly source: string, readonly from: number, readonly editing: boolean, readonly ready: boolean, readonly changed: boolean) {
    super();
  }

  eq(o: Diagram) {
    return o.source === this.source && o.editing === this.editing && o.ready === this.ready && o.changed === this.changed;
  }

  get key() {
    return `d${this.editing ? 1 : 0}${this.source}`;
  }

  get estimatedHeight() {
    const known = measured.get(this.key) ?? measured.get(`d${this.editing ? 0 : 1}${this.source}`);
    if (known) return known;
    const d = drawings.get(this.source);
    return d?.ok ? d.result.height + 24 : 180;
  }

  toDOM(view: EditorView) {
    const el = document.createElement('div');
    el.className = 'cm-diagram';
    el.setAttribute('contenteditable', 'false');
    const figure = el.appendChild(document.createElement('div'));
    figure.className = 'cm-diagram-figure';
    const note = el.appendChild(document.createElement('div'));
    note.className = 'cm-diagram-note';
    note.setAttribute('aria-live', 'polite');
    this.fill(el, view, this.from, true);
    remember(view, el, this.key);
    return el;
  }

  updateDOM(el: HTMLElement, view: EditorView) {
    this.fill(el, view, view.posAtDOM(el), false);
    remember(view, el, this.key);
    return true;
  }

  fill(el: HTMLElement, view: EditorView, from: number, fresh: boolean) {
    el.dataset.block = '';
    el.classList.toggle('cm-diagram-editing', this.editing);
    el.classList.toggle('cm-diagram-changed', this.changed);
    const figure = el.firstElementChild as HTMLElement;
    const note = el.lastElementChild as HTMLElement;
    const d = draw(this.source);
    if (!d) {
      el.classList.add('cm-diagram-pending');
      figure.style.minHeight = `${this.estimatedHeight - 24}px`;
      need('pele');
      return;
    }
    el.classList.remove('cm-diagram-pending');
    figure.style.minHeight = '';
    let shown: PeleResult | null = null;
    let stale = false;
    if (d.ok) {
      shown = d.result;
    } else if (!fresh && el.dataset.source) {
      stale = true;
    } else {
      const last = good(view.state, from);
      const old = last ? drawings.get(last) : null;
      if (old?.ok) {
        shown = old.result;
        stale = true;
      }
    }
    if (shown && el.dataset.svg !== String(shown.svg.length) + hash(shown.svg)) {
      figure.innerHTML = shown.svg;
      el.dataset.svg = String(shown.svg.length) + hash(shown.svg);
      el.dataset.source = this.source;
      const svg = figure.querySelector('svg');
      if (svg) {
        const size = fit(view, shown);
        svg.style.width = `${size.width}px`;
        svg.style.height = `${size.height}px`;
        figure.classList.toggle('cm-diagram-wide', size.scrolls);
      }
      const arriving = fresh && !seen.has(this.source) && !this.editing && performance.now() - born > 800;
      if (arriving) {
        el.classList.add('cm-diagram-arrive');
        setTimeout(() => el.classList.remove('cm-diagram-arrive'), 400);
      }
    }
    if (d.ok) {
      seen.add(this.source);
      if (good(view.state, from) !== this.source) settle(view, this.source);
    }
    el.classList.toggle('cm-diagram-stale', stale || (!d.ok && !shown && !el.dataset.source));
    el.classList.toggle('cm-diagram-empty', !d.ok && !shown && !el.dataset.source);
    note.textContent = d.ok ? '' : stale ? `Showing the last version that drew. ${d.message}` : `Can't draw this yet. ${d.message}`;
  }

  ignoreEvent(event: Event) {
    return event.type !== 'mousedown';
  }
}

const settling = new Map<EditorView, Set<string>>();
function settle(view: EditorView, source: string) {
  const waiting = settling.get(view);
  if (waiting) {
    waiting.add(source);
    return;
  }
  settling.set(view, new Set([source]));
  window.setTimeout(() => {
    const sources = settling.get(view)!;
    settling.delete(view);
    if (!view.dom.isConnected) return;
    const effects: StateEffect<{ from: number; source: string }>[] = [];
    syntaxTree(view.state).iterate({
      enter(node) {
        if (node.name !== 'FencedCode') return;
        const source = codeText(view.state, node.node);
        if (sources.has(source)) effects.push(drew.of({ from: node.from, source }));
        return false;
      },
    });
    if (effects.length) view.dispatch({ effects });
  }, 250);
}

function fenceInfo(state: EditorState, node: SyntaxNode) {
  const info = node.getChild('CodeInfo');
  return info ? state.doc.sliceString(info.from, info.to).trim().toLowerCase() : '';
}

function closed(node: SyntaxNode) {
  return node.getChildren('CodeMark').length >= 2;
}

function codeText(state: EditorState, node: SyntaxNode) {
  const text = node.getChild('CodeText');
  return text ? state.doc.sliceString(text.from, text.to) : '';
}

function touched(state: EditorState, from: number, to: number) {
  return state.selection.ranges.some((r) => r.to >= from && r.from <= to);
}

let changedRanges: (state: EditorState) => { from: number; to: number }[] = () => [];
export function reviewRanges(fn: typeof changedRanges) {
  changedRanges = fn;
}

function overlapsChange(state: EditorState, from: number, to: number) {
  return changedRanges(state).some((h) => h.from < to && h.to > from);
}

const mermaid = fold({
  nodePath: 'FencedCode',
  keepDecorationOnUnfold: true,
  buildDecorations: (state: EditorState, ref: SyntaxNodeRef) => {
    const node = ref.node;
    if (fenceInfo(state, node) !== 'mermaid' || !closed(node)) return;
    const source = codeText(state, node);
    if (!source.trim()) return;
    const editing = touched(state, node.from, node.to);
    const widget = new Diagram(source, node.from, editing, !!library('pele'), overlapsChange(state, node.from, node.to));
    if (editing) return Decoration.widget({ widget, block: true, side: -1 }).range(node.from);
    return Decoration.replace({ widget, block: true }).range(node.from, node.to);
  },
});

type Tex = { ok: true; html: string } | { ok: false; message: string };
const texes = new Map<string, Tex>();

function typeset(tex: string, display: boolean): Tex | null {
  const katex = library('katex');
  if (!katex) return null;
  const key = (display ? 'D' : 'I') + tex;
  let t = texes.get(key);
  if (t) return t;
  try {
    t = { ok: true, html: katex.renderToString(tex, { displayMode: display, throwOnError: true, output: 'html', strict: false }) };
  } catch (e: any) {
    t = { ok: false, message: String(e?.message ?? e).replace(/^KaTeX parse error: /, '') };
  }
  texes.set(key, t);
  if (texes.size > 400) texes.delete(texes.keys().next().value!);
  return t;
}

class MathView extends WidgetType {
  constructor(readonly tex: string, readonly display: boolean, readonly ready: boolean, readonly editing: boolean) {
    super();
  }

  eq(o: MathView) {
    return o.tex === this.tex && o.display === this.display && o.ready === this.ready && o.editing === this.editing;
  }

  get estimatedHeight() {
    return this.display ? measured.get(`m${this.tex}`) ?? 60 : -1;
  }

  toDOM(view: EditorView) {
    const el = document.createElement(this.display ? 'div' : 'span');
    el.className = this.display ? 'cm-math cm-math-display' : 'cm-math';
    if (this.display) el.setAttribute('contenteditable', 'false');
    this.fill(el, true);
    if (this.display) remember(view, el, `m${this.tex}`);
    return el;
  }

  updateDOM(el: HTMLElement, view: EditorView) {
    if (el.tagName !== (this.display ? 'DIV' : 'SPAN')) return false;
    this.fill(el, false);
    if (this.display) remember(view, el, `m${this.tex}`);
    return true;
  }

  fill(el: HTMLElement, fresh: boolean) {
    if (this.display) el.dataset.block = '';
    el.classList.toggle('cm-math-editing', this.editing);
    const t = typeset(this.tex, this.display);
    if (!t) {
      el.classList.add('cm-math-pending');
      el.textContent = this.tex;
      need('katex');
      return;
    }
    el.classList.remove('cm-math-pending');
    if (t.ok) {
      el.innerHTML = t.html;
      el.removeAttribute('title');
      el.classList.remove('cm-math-error');
    } else if (fresh || el.classList.contains('cm-math-pending')) {
      el.textContent = this.tex;
      el.classList.add('cm-math-error');
      el.title = t.message;
    } else {
      el.title = t.message;
    }
  }

  ignoreEvent() {
    return false;
  }
}

const math = fold({
  nodePath: 'Math',
  keepDecorationOnUnfold: true,
  buildDecorations: (state: EditorState, ref: SyntaxNodeRef, touching: boolean) => {
    const node = ref.node;
    const formula = node.getChild('MathFormula');
    if (!formula) return;
    const tex = state.doc.sliceString(formula.from, formula.to).trim();
    if (!tex) return;
    const startLine = state.doc.lineAt(node.from);
    const endLine = state.doc.lineAt(node.to);
    const block = state.doc.sliceString(node.from, node.from + 2) === '$$' && startLine.from === node.from && state.doc.sliceString(node.to, endLine.to).trim() === '';
    const ready = !!library('katex');
    if (block) {
      const widget = new MathView(tex, true, ready, touching);
      if (touching) return Decoration.widget({ widget, block: true, side: -1 }).range(startLine.from);
      return Decoration.replace({ widget, block: true }).range(startLine.from, endLine.to);
    }
    if (touching) return;
    return Decoration.replace({ widget: new MathView(tex, false, ready, false) }).range(node.from, node.to);
  },
});

type Property = { key: string; values: string[]; list: boolean };

function unquote(raw: string) {
  raw = raw.trim();
  if ((raw.startsWith('"') && raw.endsWith('"')) || (raw.startsWith("'") && raw.endsWith("'"))) return raw.slice(1, -1);
  return raw;
}

const parsedProperties = new Map<string, Property[]>();

function properties(state: EditorState, node: SyntaxNode): Property[] {
  const content = node.getChild('FrontmatterContent');
  if (!content) return [];
  const text = state.doc.sliceString(content.from, content.to);
  const cached = parsedProperties.get(text);
  if (cached) return cached;
  const found: Property[] = [];
  const at = (n: SyntaxNode) => unquote(text.slice(n.from, n.to));
  const mapping = yaml.parse(text).topNode.getChild('Document')?.getChild('BlockMapping');
  for (const pair of mapping?.getChildren('Pair') ?? []) {
    const key = pair.getChild('Key');
    if (!key) continue;
    let value: SyntaxNode | null = key.nextSibling;
    while (value && value.name === ':') value = value.nextSibling;
    const values: string[] = [];
    const list = !!value && (value.name === 'BlockSequence' || value.name === 'FlowSequence');
    if (value && list) for (const item of value.getChildren('Item')) values.push(at(item));
    else if (value) values.push(at(value));
    found.push({ key: at(key), values: values.filter((v) => v.length), list });
  }
  parsedProperties.set(text, found);
  if (parsedProperties.size > 32) parsedProperties.delete(parsedProperties.keys().next().value!);
  return found;
}

const linkish = /^\[\[([^\]|]+)(?:\|([^\]]+))?\]\]$/;

class Properties extends WidgetType {
  constructor(readonly list: Property[], readonly signature: string) {
    super();
  }

  eq(o: Properties) {
    return o.signature === this.signature;
  }

  toDOM(view: EditorView) {
    const el = document.createElement('div');
    el.className = 'cm-properties';
    el.setAttribute('contenteditable', 'false');
    el.setAttribute('role', 'table');
    el.setAttribute('aria-label', 'Properties');
    for (const p of this.list) {
      const row = el.appendChild(document.createElement('div'));
      row.className = 'cm-property';
      row.setAttribute('role', 'row');
      const key = row.appendChild(document.createElement('div'));
      key.className = 'cm-property-key';
      key.setAttribute('role', 'rowheader');
      key.textContent = p.key;
      const value = row.appendChild(document.createElement('div'));
      value.className = 'cm-property-value';
      value.setAttribute('role', 'cell');
      if (!p.values.length) {
        value.classList.add('cm-property-empty');
        value.textContent = 'Empty';
        continue;
      }
      for (const v of p.values) {
        const m = linkish.exec(v);
        const chip = value.appendChild(document.createElement('span'));
        if (m) {
          chip.className = 'cm-wikilink';
          chip.dataset.note = m[1].trim();
          chip.textContent = (m[2] ?? m[1]).trim();
        } else if (/^(true|false)$/i.test(v) && !p.list) {
          chip.className = 'cm-property-flag';
          chip.dataset.on = String(/^true$/i.test(v));
          chip.textContent = /^true$/i.test(v) ? 'Yes' : 'No';
        } else if (p.list || /^(tags|aliases|cssclasses)$/i.test(p.key)) {
          chip.className = /^tags?$/i.test(p.key) ? 'cm-tag' : 'cm-property-chip';
          chip.textContent = /^tags?$/i.test(p.key) && !v.startsWith('#') ? `#${v}` : v;
        } else {
          chip.className = 'cm-property-text';
          chip.textContent = v;
        }
      }
    }
    remember(view, el, `p${this.signature}`);
    return el;
  }

  get estimatedHeight() {
    return measured.get(`p${this.signature}`) ?? this.list.length * 26 + 18;
  }

  ignoreEvent() {
    return false;
  }
}

const frontmatter = fold({
  nodePath: 'Frontmatter',
  buildDecorations: (state: EditorState, ref: SyntaxNodeRef) => {
    const node = ref.node;
    const list = properties(state, node);
    const end = state.doc.lineAt(node.to).to;
    if (!list.length) return;
    return Decoration.replace({ widget: new Properties(list, JSON.stringify(list)), block: true }).range(node.from, end);
  },
});

const families: Record<string, string[]> = {
  note: ['note'],
  info: ['info', 'todo'],
  abstract: ['abstract', 'summary', 'tldr'],
  tip: ['tip', 'hint', 'important'],
  success: ['success', 'check', 'done'],
  question: ['question', 'help', 'faq'],
  warning: ['warning', 'caution', 'attention'],
  failure: ['failure', 'fail', 'missing'],
  danger: ['danger', 'error', 'bug'],
  example: ['example'],
  quote: ['quote', 'cite'],
};

const familyOf = (type: string) => Object.entries(families).find(([, names]) => names.includes(type))?.[0] ?? 'note';

const icons: Record<string, string> = {
  note: 'M4 20h4l10.5-10.5a2.1 2.1 0 0 0-4-4L4 16v4zM13.5 6.5l4 4',
  info: 'M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20zM12 16v-4M12 8h.01',
  abstract: 'M9 4h6v3H9zM8 5H6v16h12V5h-2M9 12h6M9 16h6',
  tip: 'M8.5 14.5A2.5 2.5 0 0 0 11 12c0-1.4-.5-2-1-3-1.1-2.1-.2-4 2-6 .5 2.5 2 4.9 4 6.5 2 1.6 3 3.5 3 5.5a7 7 0 1 1-14 0c0-1.2.4-2.3 1-3.2a2.5 2.5 0 0 0 2.5 2.7z',
  success: 'M20 6 9 17l-5-5',
  question: 'M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20zM9.1 9a3 3 0 0 1 5.8 1c0 2-3 3-3 3M12 17h.01',
  warning: 'M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0zM12 9v4M12 17h.01',
  failure: 'M18 6 6 18M6 6l12 12',
  danger: 'M13 2 3 14h9l-1 8 10-12h-9l1-8z',
  example: 'M8 6h13M8 12h13M8 18h13M3 6h.01M3 12h.01M3 18h.01',
  quote: 'M3 21c3 0 7-1 7-8V5c0-1.3-.8-2-2-2H4c-1.3 0-2 .8-2 2v6c0 1.3.8 2 2 2 1 0 1 0 1 1v1c0 1-1 2-2 2s-1 0-1 1v3c0 1 0 1 1 1zM15 21c3 0 7-1 7-8V5c0-1.3-.8-2-2-2h-4c-1.3 0-2 .8-2 2v6c0 1.3.8 2 2 2h.8c0 2.3-.4 4-2.8 4v3c0 1 0 1 1 1z',
};

function svgIcon(path: string, cls: string) {
  const ns = 'http://www.w3.org/2000/svg';
  const svg = document.createElementNS(ns, 'svg');
  svg.setAttribute('viewBox', '0 0 24 24');
  svg.setAttribute('class', cls);
  svg.setAttribute('aria-hidden', 'true');
  const p = document.createElementNS(ns, 'path');
  p.setAttribute('d', path);
  svg.appendChild(p);
  return svg;
}

class CalloutHead extends WidgetType {
  constructor(readonly family: string, readonly title: string | null, readonly fold: '' | '+' | '-', readonly open: boolean) {
    super();
  }

  eq(o: CalloutHead) {
    return o.family === this.family && o.title === this.title && o.fold === this.fold && o.open === this.open;
  }

  toDOM() {
    const el = document.createElement('span');
    el.className = 'cm-callout-head';
    el.appendChild(svgIcon(icons[this.family], 'cm-callout-icon'));
    if (this.title) {
      const t = el.appendChild(document.createElement('span'));
      t.className = 'cm-callout-default-title';
      t.textContent = this.title;
    }
    return el;
  }

  ignoreEvent() {
    return false;
  }
}

class Chevron extends WidgetType {
  constructor(readonly open: boolean) {
    super();
  }

  eq(o: Chevron) {
    return o.open === this.open;
  }

  toDOM() {
    const el = document.createElement('button');
    el.className = 'cm-callout-fold';
    el.dataset.open = String(this.open);
    el.setAttribute('aria-label', this.open ? 'Collapse' : 'Expand');
    el.setAttribute('aria-expanded', String(this.open));
    el.appendChild(svgIcon('m9 18 6-6-6-6', 'cm-callout-chevron'));
    return el;
  }

  ignoreEvent(event: Event) {
    return event.type !== 'mousedown';
  }
}

function isOpen(state: EditorState, from: number) {
  let open = false;
  state.field(opened).between(from, from, (f) => {
    if (f === from) open = true;
  });
  return open;
}

const callouts = fold({
  nodePath: 'Blockquote',
  keepDecorationOnUnfold: true,
  buildDecorations: (state: EditorState, ref: SyntaxNodeRef, touching: boolean) => {
    const node = ref.node;
    const para = node.getChild('Paragraph');
    const mark = para?.firstChild;
    if (!para || !mark || mark.name !== 'CalloutMark') return;
    const raw = state.doc.sliceString(mark.from, mark.to);
    const fold = (raw.endsWith('+') || raw.endsWith('-') ? raw.slice(-1) : '') as '' | '+' | '-';
    const type = raw.slice(2, raw.indexOf(']')).toLowerCase();
    const family = familyOf(type);
    const first = state.doc.lineAt(node.from);
    const last = state.doc.lineAt(node.to);
    const titled = state.doc.sliceString(mark.to, first.to).trim().length > 0;
    const collapsed = fold === '-' ? !isOpen(state, node.from) : fold === '+' ? isOpen(state, node.from) : false;
    const hideBody = collapsed && !touching && last.number > first.number;
    const out: Range<Decoration>[] = [];
    for (let n = first.number; n <= (hideBody ? first.number : last.number); n++) {
      const line = state.doc.line(n);
      const cls = ['cm-callout', `cm-callout-${family}`, n === first.number ? 'cm-callout-first' : '', n === last.number || hideBody ? 'cm-callout-last' : ''].join(' ');
      out.push(Decoration.line({ class: cls, attributes: { 'data-callout': type } }).range(line.from));
    }
    if (touching) {
      out.push(Decoration.mark({ class: 'cm-callout-source' }).range(mark.from, mark.to));
    } else {
      const titleText = titled ? null : type.charAt(0).toUpperCase() + type.slice(1).replace(/-/g, ' ');
      const end = Math.min(first.to, mark.to + (state.doc.sliceString(mark.to, mark.to + 1) === ' ' ? 1 : 0));
      out.push(Decoration.replace({ widget: new CalloutHead(family, titleText, fold, !collapsed) }).range(mark.from, end));
      if (end < first.to) out.push(Decoration.mark({ class: 'cm-callout-title' }).range(end, first.to));
      if (fold) out.push(Decoration.widget({ widget: new Chevron(!collapsed), side: 1 }).range(first.to));
      if (hideBody) out.push(Decoration.replace({}).range(first.to, last.to));
    }
    return out;
  },
});

const imageExt = /\.(png|jpe?g|gif|webp|svg|bmp|avif|heic|tiff?)$/i;
const mediaExt = /\.(mp4|mov|webm|m4v|mp3|m4a|wav|ogg|flac|aac)$/i;

let nestedExtensions: () => Extension[] = () => [];
export function nested(fn: () => Extension[]) {
  nestedExtensions = fn;
}

function size(alias: string | null) {
  const m = alias ? /^(\d+)(?:x(\d+))?$/.exec(alias.trim()) : null;
  return m ? { width: Number(m[1]), height: m[2] ? Number(m[2]) : undefined } : null;
}

class EmbedView extends WidgetType {
  constructor(readonly target: string, readonly alias: string | null, readonly payload: Payload | undefined, readonly block: boolean, readonly editing: boolean) {
    super();
  }

  eq(o: EmbedView) {
    return o.target === this.target && o.alias === this.alias && o.payload === this.payload && o.block === this.block && o.editing === this.editing;
  }

  get estimatedHeight() {
    const known = measured.get(`e${this.block}${this.target}|${this.alias}`);
    if (known) return known;
    const p = this.payload;
    if (p?.kind === 'image' && p.width && p.height) {
      const s = size(this.alias);
      const w = Math.min(s?.width ?? p.width, 620);
      return (p.height / p.width) * w + 12;
    }
    return p?.kind === 'note' ? 220 : 44;
  }

  toDOM(view: EditorView) {
    const el = document.createElement(this.block ? 'div' : 'span');
    el.className = `cm-embed${this.block ? ' cm-embed-block' : ''}`;
    if (this.block) {
      el.dataset.block = '';
      if (this.payload) remember(view, el, `e${this.block}${this.target}|${this.alias}`);
    }
    el.setAttribute('contenteditable', 'false');
    const p = this.payload;
    if (!p && view.state.facet(depth) >= 1) return el;
    if (!p) {
      el.classList.add('cm-embed-pending');
      ask(this.target);
      if (this.block) el.style.minHeight = '44px';
      return el;
    }
    if (p.kind === 'image') {
      const img = el.appendChild(document.createElement('img'));
      img.src = p.url;
      img.alt = this.alias && !size(this.alias) ? this.alias : this.target;
      img.decoding = 'async';
      const s = size(this.alias);
      if (s?.width) img.style.width = `${s.width}px`;
      if (s?.height) img.style.height = `${s.height}px`;
      if (p.width && p.height) img.style.aspectRatio = `${p.width} / ${p.height}`;
      if (!s?.width && p.width) img.style.width = `${p.width}px`;
      el.classList.add('cm-embed-image');
      return el;
    }
    if (p.kind === 'media') {
      const media = el.appendChild(document.createElement(p.media));
      media.src = p.url;
      media.controls = true;
      media.preload = 'metadata';
      el.classList.add('cm-embed-media');
      return el;
    }
    if (p.kind === 'missing' || p.kind === 'file' || p.kind === 'link') {
      const chip = el.appendChild(document.createElement('span'));
      chip.className = 'cm-embed-chip';
      chip.dataset.note = p.kind === 'file' ? '' : this.target;
      if (p.kind === 'link') {
        chip.textContent = this.alias ?? p.title;
        el.classList.add('cm-embed-link');
        return el;
      }
      if (p.kind === 'file') chip.dataset.url = p.url;
      chip.textContent = p.kind === 'missing' ? `“${p.title}” doesn't exist yet` : p.name;
      el.classList.add(p.kind === 'missing' ? 'cm-embed-missing' : 'cm-embed-file');
      return el;
    }
    el.classList.add('cm-embed-note');
    const head = el.appendChild(document.createElement('div'));
    head.className = 'cm-embed-title cm-wikilink';
    head.dataset.note = this.target.split('#')[0] ? this.target : p.title;
    const [, sub] = this.target.split('#');
    head.textContent = this.alias ?? (sub && !sub.startsWith('^') ? `${p.title} › ${sub}` : p.title);
    const body = el.appendChild(document.createElement('div'));
    body.className = 'cm-embed-body';
    if (view.state.facet(depth) >= 1) {
      body.textContent = p.text.slice(0, 600);
      return el;
    }
    const inner = new EditorView({
      parent: body,
      state: EditorState.create({
        doc: `${p.text}\n`,
        selection: { anchor: p.text.length + 1 },
        extensions: [nestedExtensions(), depth.of(view.state.facet(depth) + 1), EditorState.readOnly.of(true), EditorView.editable.of(false)],
      }),
    });
    if (p.embeds) inner.dispatch({ effects: setEmbeds.of(p.embeds), selection: inner.state.selection });
    views.add(inner);
    (el as any).inner = inner;
    return el;
  }

  destroy(dom: HTMLElement) {
    const inner = (dom as any).inner as EditorView | undefined;
    if (!inner) return;
    views.delete(inner);
    inner.destroy();
  }

  ignoreEvent(event: Event) {
    return event.type !== 'mousedown';
  }
}

const asked = new Set<string>();
export function forgetEmbeds() {
  asked.clear();
  made.clear();
}

function ask(target: string) {
  if (asked.has(target)) return;
  asked.add(target);
  post({ type: 'embed', target });
}

const made = new Map<string, { payload: Payload | undefined; deco: Decoration }>();

function embedDecoration(state: EditorState, target: string, alias: string | null, from: number, to: number, touching: boolean) {
  let payload = state.field(embedded).get(target);
  const line = state.doc.lineAt(from);
  const block = state.doc.sliceString(line.from, from).trim() === '' && state.doc.sliceString(to, line.to).trim() === '';
  if (state.facet(depth) >= 1) {
    if (!payload) return;
    if (payload.kind === 'note') payload = { kind: 'link', title: payload.title };
  }
  if (touching && (!block || !payload || payload.kind === 'missing')) return;
  const key = `${target}\u0000${alias}\u0000${block}\u0000${touching}`;
  const hit = made.get(key);
  let deco = hit && hit.payload === payload ? hit.deco : null;
  if (!deco) {
    const widget = new EmbedView(target, alias, payload, block, touching);
    deco = touching ? Decoration.widget({ widget, block: true, side: -1 }) : Decoration.replace({ widget, block });
    made.set(key, { payload, deco });
  }
  if (touching) return deco.range(line.from);
  return block ? deco.range(line.from, line.to) : deco.range(from, to);
}

const embeds = fold({
  nodePath: 'Embed',
  keepDecorationOnUnfold: true,
  buildDecorations: (state: EditorState, ref: SyntaxNodeRef, touching: boolean) => {
    const inner = state.doc.sliceString(ref.from + 3, ref.to - 2);
    const pipe = inner.search(/\\?\|/);
    const target = (pipe < 0 ? inner : inner.slice(0, pipe)).trim();
    if (!target) return;
    const alias = pipe < 0 ? null : inner.slice(pipe + (inner[pipe] === '\\' ? 2 : 1)).trim();
    const d = embedDecoration(state, target, alias, ref.from, ref.to, touching);
    if (!touching) return d;
    const source = Decoration.mark({ class: 'cm-embed-source' }).range(ref.from, ref.to);
    return d ? [d, source] : source;
  },
});

const images = fold({
  nodePath: 'Image',
  keepDecorationOnUnfold: true,
  buildDecorations: (state: EditorState, ref: SyntaxNodeRef, touching: boolean) => {
    const node = ref.node;
    const url = node.getChild('URL');
    if (!url) return;
    const src = state.doc.sliceString(url.from, url.to).trim();
    const marks = node.getChildren('LinkMark');
    const label = marks.length >= 2 ? state.doc.sliceString(marks[0].to, marks[1].from) : '';
    const sized = /\|(\d+(?:x\d+)?)$/.exec(label);
    if (/^https?:/i.test(src)) {
      const payload: Payload = { kind: 'image', url: src };
      const line = state.doc.lineAt(node.from);
      const block = state.doc.sliceString(line.from, node.from).trim() === '' && state.doc.sliceString(node.to, line.to).trim() === '';
      const widget = new EmbedView(src, sized ? sized[1] : null, payload, block, touching);
      if (touching) return block ? Decoration.widget({ widget, block: true, side: -1 }).range(line.from) : undefined;
      return block ? Decoration.replace({ widget, block: true }).range(line.from, line.to) : Decoration.replace({ widget }).range(node.from, node.to);
    }
    return embedDecoration(state, `path:${safeDecode(src)}`, sized ? sized[1] : null, node.from, node.to, touching);
  },
});

function safeDecode(s: string) {
  try {
    return decodeURI(s);
  } catch {
    return s;
  }
}

class Sup extends WidgetType {
  constructor(readonly label: string) { super(); }
  eq(o: Sup) { return o.label === this.label; }
  toDOM() {
    const el = document.createElement('sup');
    el.className = 'cm-footnote';
    el.textContent = this.label;
    return el;
  }
}

class Folded extends WidgetType {
  eq() { return true; }
  toDOM() {
    const el = document.createElement('div');
    el.className = 'cm-comment-block';
    el.textContent = 'Hidden comment';
    return el;
  }
  ignoreEvent() { return false; }
}

const hide = Decoration.replace({});

const marks = [
  fold({
    nodePath: 'WikiLink',
    keepDecorationOnUnfold: true,
    buildDecorations: (state: EditorState, ref: SyntaxNodeRef, touching: boolean) => {
      const node = ref.node;
      const t = node.getChild('WikiTarget');
      if (!t) return;
      const target = state.doc.sliceString(t.from, t.to).trim();
      if (touching) return Decoration.mark({ class: 'cm-wikilink-source', attributes: { 'data-note': target } }).range(node.from, node.to);
      const alias = node.getChild('WikiAlias');
      const labelFrom = alias ? alias.from : t.from;
      const labelTo = alias ? alias.to : t.to;
      const out = [hide.range(node.from, labelFrom), Decoration.mark({ class: 'cm-wikilink', attributes: { 'data-note': target } }).range(labelFrom, labelTo), hide.range(labelTo, node.to)];
      return out.filter((r) => r.to > r.from);
    },
  }),
  fold({
    nodePath: 'Highlight',
    keepDecorationOnUnfold: true,
    buildDecorations: (state: EditorState, ref: SyntaxNodeRef, touching: boolean) => {
      const node = ref.node;
      const marks = node.getChildren('HighlightMark');
      const out: Range<Decoration>[] = [Decoration.mark({ class: 'cm-highlight' }).range(node.from, node.to)];
      if (!touching) for (const m of marks) out.push(hide.range(m.from, m.to));
      return out;
    },
  }),
  fold({
    nodePath: 'BlockId',
    keepDecorationOnUnfold: true,
    buildDecorations: (_state: EditorState, ref: SyntaxNodeRef, touching: boolean) =>
      touching ? Decoration.mark({ class: 'cm-block-id' }).range(ref.from, ref.to) : hide.range(ref.from, ref.to),
  }),
  fold({
    nodePath: 'FootnoteRef',
    buildDecorations: (state: EditorState, ref: SyntaxNodeRef) => {
      const line = state.doc.lineAt(ref.from);
      if (line.from === ref.from && state.doc.sliceString(ref.to, ref.to + 1) === ':') {
        return Decoration.replace({ widget: new Sup(state.doc.sliceString(ref.from + 2, ref.to - 1)) }).range(ref.from, ref.to + 1);
      }
      return Decoration.replace({ widget: new Sup(state.doc.sliceString(ref.from + 2, ref.to - 1)) }).range(ref.from, ref.to);
    },
  }),
  fold({
    nodePath: 'Tag',
    keepDecorationOnUnfold: true,
    buildDecorations: (_state: EditorState, ref: SyntaxNodeRef) => Decoration.mark({ class: 'cm-tag' }).range(ref.from, ref.to),
  }),
];

const inline = [
  fold({
    nodePath: 'Comment',
    keepDecorationOnUnfold: true,
    buildDecorations: (_state: EditorState, ref: SyntaxNodeRef, touching: boolean) =>
      touching ? Decoration.mark({ class: 'cm-comment' }).range(ref.from, ref.to) : hide.range(ref.from, ref.to),
  }),
  fold({
    nodePath: 'CommentBlock',
    keepDecorationOnUnfold: true,
    buildDecorations: (state: EditorState, ref: SyntaxNodeRef, touching: boolean) => {
      const first = state.doc.lineAt(ref.from);
      const last = state.doc.lineAt(ref.to);
      if (touching) {
        const out: Range<Decoration>[] = [];
        for (let n = first.number; n <= last.number; n++) out.push(Decoration.line({ class: 'cm-comment-line' }).range(state.doc.line(n).from));
        return out;
      }
      return Decoration.replace({ widget: new Folded(), block: true }).range(first.from, last.to);
    },
  }),
];

const allowed = new Set(['p', 'div', 'span', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'br', 'b', 'i', 'u', 's', 'em', 'strong', 'mark', 'sub', 'sup', 'kbd', 'code', 'pre', 'ul', 'ol', 'li', 'a', 'img', 'table', 'thead', 'tbody', 'tr', 'th', 'td', 'details', 'summary', 'blockquote', 'hr', 'iframe', 'small', 'abbr', 'center', 'font', 'del', 'ins', 'cite', 'q', 'dl', 'dt', 'dd', 'figure', 'figcaption', 'caption', 'section', 'article', 'aside', 'header', 'footer', 'nav', 'video', 'audio', 'source']);
const kept = new Set(['href', 'src', 'alt', 'title', 'width', 'height', 'colspan', 'rowspan', 'open', 'controls']);
const safeUrl = (v: string) => /^(https?:|quill-file:|mailto:|#)/i.test(v.trim());

function clean(source: string) {
  const doc = new DOMParser().parseFromString(`<body>${source}</body>`, 'text/html');
  const walk = (node: Element) => {
    for (const child of Array.from(node.children)) {
      const tag = child.tagName.toLowerCase();
      if (!allowed.has(tag)) {
        if (['script', 'style', 'object', 'embed', 'form', 'input', 'button', 'textarea', 'select', 'link', 'meta'].includes(tag)) child.remove();
        else child.replaceWith(...Array.from(child.childNodes));
        continue;
      }
      for (const attr of Array.from(child.attributes)) {
        const name = attr.name.toLowerCase();
        if (!kept.has(name) || ((name === 'href' || name === 'src') && !safeUrl(attr.value))) child.removeAttribute(attr.name);
      }
      if (tag === 'iframe') {
        child.setAttribute('sandbox', 'allow-scripts allow-popups');
        child.setAttribute('loading', 'lazy');
        child.setAttribute('referrerpolicy', 'no-referrer');
      }
      walk(child);
    }
  };
  walk(doc.body);
  return doc.body.innerHTML;
}

class HtmlView extends WidgetType {
  constructor(readonly source: string) { super(); }
  eq(o: HtmlView) { return o.source === this.source; }
  toDOM() {
    const el = document.createElement('div');
    el.className = 'cm-html';
    el.setAttribute('contenteditable', 'false');
    el.innerHTML = clean(this.source);
    return el;
  }
  ignoreEvent() { return false; }
}

class Break extends WidgetType {
  eq() { return true; }
  toDOM() { return document.createElement('br'); }
}

const styled: Record<string, string> = { u: 'cm-html-u', ins: 'cm-html-u', s: 'cm-html-s', del: 'cm-html-s', strike: 'cm-html-s', b: 'cm-html-b', strong: 'cm-html-b', i: 'cm-html-i', em: 'cm-html-i', mark: 'cm-highlight', kbd: 'cm-html-kbd', sup: 'cm-html-sup', sub: 'cm-html-sub', small: 'cm-html-small', code: 'cm-inline-code' };

function tagName(text: string) {
  const m = /^<\/?([a-zA-Z][\w-]*)/.exec(text);
  return m ? m[1].toLowerCase() : null;
}

const html = [
  fold({
    nodePath: 'HTMLBlock',
    buildDecorations: (state: EditorState, ref: SyntaxNodeRef) => {
      const first = state.doc.lineAt(ref.from);
      const last = state.doc.lineAt(Math.max(ref.from, ref.to - (state.doc.sliceString(ref.to - 1, ref.to) === '\n' ? 1 : 0)));
      const source = state.doc.sliceString(first.from, last.to);
      if (/^\s*<!--/.test(source)) return;
      return Decoration.replace({ widget: new HtmlView(source), block: true }).range(first.from, last.to);
    },
  }),
  fold({
    nodePath: 'HTMLTag',
    keepDecorationOnUnfold: true,
    buildDecorations: (state: EditorState, ref: SyntaxNodeRef, touching: boolean) => {
      const text = state.doc.sliceString(ref.from, ref.to);
      const name = tagName(text);
      if (!name) return;
      if (touching) return Decoration.mark({ class: 'cm-html-source' }).range(ref.from, ref.to);
      if (name === 'br') return Decoration.replace({ widget: new Break() }).range(ref.from, ref.to);
      const out: Range<Decoration>[] = [hide.range(ref.from, ref.to)];
      if (!text.startsWith('</') && styled[name]) {
        const line = state.doc.lineAt(ref.from);
        const rest = state.doc.sliceString(ref.to, line.to);
        const close = rest.toLowerCase().indexOf(`</${name}`);
        if (close > 0) out.push(Decoration.mark({ class: styled[name] }).range(ref.to, ref.to + close));
      }
      return out;
    },
  }),
];

const clicks = EditorView.domEventHandlers({
  mousedown(event, view) {
    if (event.button !== 0) return false;
    const target = event.target as HTMLElement;
    const fold = target.closest('.cm-callout-fold') as HTMLElement | null;
    if (fold) {
      event.preventDefault();
      let node: SyntaxNode | null = syntaxTree(view.state).resolveInner(view.posAtDOM(fold), -1);
      while (node && node.name !== 'Blockquote') node = node.parent;
      if (node) refresh(view, [toggled.of(node.from)]);
      return true;
    }
    const chip = target.closest('.cm-embed-chip, .cm-embed-title, .cm-properties .cm-wikilink') as HTMLElement | null;
    if (chip) {
      event.preventDefault();
      if (chip.dataset.url) post({ type: 'link', url: chip.dataset.url });
      else if (chip.dataset.note) post({ type: 'note', title: chip.dataset.note });
      return true;
    }
    const anchor = target.closest('.cm-diagram a') as HTMLAnchorElement | SVGAElement | null;
    if (anchor) {
      event.preventDefault();
      const href = anchor.getAttribute('href') ?? anchor.getAttribute('xlink:href');
      if (href && /^(https?:|mailto:)/i.test(href.trim())) post({ type: 'link', url: href.trim() });
      return true;
    }
    const inner = target.closest('.cm-embed-body a, .cm-embed-body .cm-wikilink') as HTMLElement | null;
    if (inner?.dataset.note) {
      event.preventDefault();
      post({ type: 'note', title: inner.dataset.note });
      return true;
    }
    const link = target.closest('.cm-html a[href]') as HTMLAnchorElement | null;
    if (link) {
      event.preventDefault();
      if (/^(https?:|mailto:)/i.test(link.getAttribute('href') ?? '')) post({ type: 'link', url: link.href });
      return true;
    }
    if (target.closest('.cm-html iframe, .cm-html summary')) return false;
    const block = target.closest('.cm-diagram, .cm-math-display, .cm-properties, .cm-embed-block, .cm-comment-block, .cm-html') as HTMLElement | null;
    if (!block) return false;
    if (block.classList.contains('cm-embed-block') && block.querySelector('video, audio') && target.closest('video, audio')) return false;
    event.preventDefault();
    const pos = view.posAtDOM(block);
    const node = blockAt(view, block);
    let anchorPos = pos;
    if (node?.name === 'FencedCode') anchorPos = Math.min(view.state.doc.lineAt(node.from).to + 1, node.to);
    else if (node?.name === 'Frontmatter') anchorPos = Math.min(view.state.doc.lineAt(node.from).to + 1, node.to);
    else if (node?.name === 'Math') anchorPos = Math.min(node.from + 2, node.to);
    else if (block.classList.contains('cm-embed-block')) {
      const line = view.state.doc.lineAt(pos);
      anchorPos = line.to;
    }
    view.dispatch({ selection: EditorSelection.cursor(anchorPos), userEvent: 'select.pointer' });
    view.focus();
    return true;
  },
});

const inputs = rebuilds.of((tr) => {
  if (tr.effects.some((e) => e.is(refreshed) || e.is(setEmbeds) || e.is(drew) || e.is(toggled))) return true;
  const before = changedRanges(tr.startState), after = changedRanges(tr.state);
  if (before === after) return false;
  if (before.length !== after.length) return true;
  return after.some((h, i) => h.from !== tr.changes.mapPos(before[i].from, -1) || h.to !== tr.changes.mapPos(before[i].to, 1));
});

const decorated = [inputs, folds([mermaid, math, frontmatter, callouts, embeds, images, ...inline, ...html]), visible(marks)];

export const blocks: Extension = [embedded, drawn, opened, decorated, clicks];
export const nestedBlocks: Extension = [embedded, drawn, opened, decorated];

export function startAfterProperties(state: EditorState) {
  const first = syntaxTree(state).topNode.firstChild;
  if (first?.name !== 'Frontmatter' || state.selection.main.head > first.to) return null;
  const line = state.doc.lineAt(Math.min(first.to + 1, state.doc.length));
  return line.from;
}

export function preload(text: string) {
  const wanted: Library[] = [];
  if (/^\s*```+\s*mermaid/im.test(text)) wanted.push('pele');
  if (text.includes('$')) wanted.push('katex');
  return Promise.all(wanted.map(need));
}
