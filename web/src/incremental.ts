import { syntaxTree } from '@codemirror/language';
import { Facet, type EditorState, type Range, type Transaction } from '@codemirror/state';
import type { Decoration, DecorationSet } from '@codemirror/view';
import type { Tree } from '@lezer/common';

export const rebuilds = Facet.define<(tr: Transaction) => boolean>();

type Build = (state: EditorState, from?: number, to?: number, out?: Range<Decoration>[]) => DecorationSet;

const seen = new WeakMap<Tree, number[]>();

function blocks(tree: Tree) {
  const known = seen.get(tree);
  if (known) return known;
  const out: number[] = [];
  seen.set(tree, out);
  const c = tree.cursor();
  if (!c.firstChild()) return out;
  do out.push(c.from, c.to, c.type.id);
  while (c.nextSibling());
  return out;
}

export function outside(node: { from: number; to: number }, from: number, to: number) {
  return node.from < from || node.to > to;
}

export function incremental(deco: DecorationSet, tr: Transaction, build: Build): DecorationSet {
  const before = syntaxTree(tr.startState);
  const after = syntaxTree(tr.state);
  if (tr.reconfigured || tr.state.facet(rebuilds).some((f) => f(tr))) return build(tr.state);
  if (!tr.docChanged && !tr.selection && before === after) return deco.map(tr.changes);
  const touched: number[] = [];
  tr.changes.iterChangedRanges((_fa, _ta, from, to) => touched.push(from, to));
  for (const r of tr.startState.selection.ranges) touched.push(tr.changes.mapPos(r.from, -1), tr.changes.mapPos(r.to, 1));
  for (const r of tr.state.selection.ranges) touched.push(r.from, r.to);
  const old = blocks(before);
  const now = blocks(after);
  const length = tr.state.doc.length;
  const dirty: number[] = [];
  const mark = (from: number, to: number) => {
    if (dirty.length && dirty[dirty.length - 1] >= from - 1) dirty[dirty.length - 1] = Math.max(to, dirty[dirty.length - 1]);
    else dirty.push(from, to);
  };
  const hit = (from: number, to: number) => {
    for (let k = 0; k < touched.length; k += 2) if (touched[k] <= to && touched[k + 1] >= from) return true;
    return false;
  };
  let i = 0;
  for (let j = 0; j < now.length; j += 3) {
    const from = now[j], to = now[j + 1], type = now[j + 2];
    const start = j ? now[j - 2] + 1 : 0;
    let same = false;
    while (i < old.length) {
      const f = tr.changes.mapPos(old[i], 1), t = tr.changes.mapPos(old[i + 1], -1);
      if (f < from) { i += 3; continue; }
      same = f === from && t === to && old[i + 2] === type;
      break;
    }
    if (!same || hit(start, to)) mark(start, to);
  }
  const tail = now.length ? now[now.length - 2] + 1 : 0;
  if (tail <= length && (hit(tail, length) || old.length > now.length)) mark(tail, length);
  let next = deco.map(tr.changes);
  if (!dirty.length) return next;
  const add: Range<Decoration>[] = [];
  for (let k = 0; k < dirty.length; k += 2) {
    const from = dirty[k], to = dirty[k + 1];
    next = next.update({ filterFrom: from, filterTo: to, filter: (f, t) => t < from || f > to });
    build(tr.state, from, to, add);
  }
  return next.update({ add, sort: true });
}
