import type { EditorView } from '@codemirror/view';

export function wrap(view: EditorView, marker: string) {
  const { state } = view;
  const sel = state.selection.main;
  const m = marker.length;
  const doc = state.doc;
  const at = (from: number, to: number) => (from >= 0 && to <= doc.length ? doc.sliceString(from, to) : '');
  const outerFrom = sel.from - m;
  const outerTo = sel.to + m;
  const doubled = m === 1 && at(outerFrom - 1, outerFrom) === marker && at(outerTo, outerTo + 1) === marker;
  if (!doubled && at(outerFrom, sel.from) === marker && at(sel.to, outerTo) === marker) {
    view.dispatch({
      changes: { from: outerFrom, to: outerTo, insert: doc.sliceString(sel.from, sel.to) },
      selection: { anchor: outerFrom, head: outerFrom + (sel.to - sel.from) },
      userEvent: 'input.format',
    });
    return;
  }
  view.dispatch({
    changes: { from: sel.from, to: sel.to, insert: marker + doc.sliceString(sel.from, sel.to) + marker },
    selection: { anchor: sel.from + m, head: sel.to + m },
    userEvent: 'input.format',
  });
}

export function heading(view: EditorView, level: number) {
  const { state } = view;
  const caret = state.selection.main;
  const line = state.doc.lineAt(caret.head);
  const run = /^#*/.exec(line.text)![0].length;
  const after = line.text[run];
  const hashes = after === undefined || after === ' ' ? run : 0;
  const existing = hashes > 0 ? hashes + (line.text[hashes] === ' ' ? 1 : 0) : 0;
  const next = level === 0 || level === hashes ? '' : '#'.repeat(level) + ' ';
  const delta = next.length - existing;
  view.dispatch({
    changes: { from: line.from, to: line.from + existing, insert: next },
    selection: { anchor: Math.max(line.from + next.length, caret.anchor + delta), head: Math.max(line.from + next.length, caret.head + delta) },
    userEvent: 'input.format',
  });
}
