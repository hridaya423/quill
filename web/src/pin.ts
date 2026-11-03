import { syntaxTree } from '@codemirror/language';
import { EditorSelection, type Transaction } from '@codemirror/state';
import { BlockType, EditorView, type BlockInfo } from '@codemirror/view';

function replaced(block: BlockInfo, pos: number): BlockInfo | null {
  if (Array.isArray(block.type)) {
    for (const part of block.type as readonly BlockInfo[]) {
      const hit = part.from <= pos && part.to >= pos ? replaced(part, pos) : null;
      if (hit) return hit;
    }
    return null;
  }
  return block.type === BlockType.WidgetRange && block.from < block.to ? block : null;
}

function live(view: EditorView, pos: number) {
  for (let node: any = syntaxTree(view.state).resolveInner(pos, -1); node; node = node.parent) {
    if (node.name === 'Math') return true;
    if (node.name === 'FencedCode') {
      const info = node.getChild('CodeInfo');
      return !!info && view.state.sliceDoc(info.from, info.to).trim().toLowerCase() === 'mermaid';
    }
  }
  return false;
}

type Anchor = { block: number } | { pos: number };

function blockAt(view: EditorView, from: number) {
  for (const el of view.contentDOM.querySelectorAll('[data-block]')) if (view.posAtDOM(el) === from) return el;
  return null;
}

function top(view: EditorView, anchor: Anchor): number | null {
  if ('block' in anchor) return blockAt(view, anchor.block)?.getBoundingClientRect().top ?? null;
  if (anchor.pos > view.state.doc.length) return null;
  const c = view.coordsAtPos(anchor.pos, 1) ?? view.coordsAtPos(anchor.pos, -1);
  return c ? c.top : null;
}

function visible(view: EditorView, y: number) {
  const box = view.scrollDOM.getBoundingClientRect();
  return y >= box.top - 4 && y <= box.bottom + 4;
}

export function dispatchPinned(trs: readonly Transaction[], view: EditorView) {
  const last = trs[trs.length - 1];
  const typed = trs.some((t) => t.docChanged && (t.isUserEvent('input') || t.isUserEvent('delete')));
  const selected = !trs.some((t) => t.docChanged) && !!last.selection && trs.some((t) => t.isUserEvent('select'));
  let anchor: Anchor | null = null;
  let screen: number | null = null;
  if (selected) {
    const head = last.state.selection.main.head;
    const block = replaced(view.lineBlockAt(head), head);
    anchor = block && blockAt(view, block.from) ? { block: block.from } : { pos: head };
    screen = top(view, anchor);
  } else if (typed && live(view, view.state.selection.main.head)) {
    let start = -1;
    for (const t of trs) t.changes.iterChangedRanges((fromA) => { if (start < 0) start = fromA; });
    const from = view.state.doc.lineAt(Math.max(0, start)).from;
    screen = top(view, { pos: from });
    let mapped = from;
    for (const t of trs) mapped = t.changes.mapPos(mapped, -1);
    anchor = { pos: mapped };
  }
  view.update(trs);
  if (!anchor || screen === null || !visible(view, screen)) return;
  if ('pos' in anchor) {
    const margin = screen - view.scrollDOM.getBoundingClientRect().top;
    view.dispatch({ effects: EditorView.scrollIntoView(EditorSelection.cursor(anchor.pos, 1), { y: 'start', yMargin: margin }) });
  }
  hold(view, anchor, screen, 4);
}

function hold(view: EditorView, anchor: Anchor, screen: number, tries: number) {
  view.requestMeasure({
    key: 'quill-pin',
    read: (v) => top(v, anchor),
    write: (now, v) => {
      if (now === null) return;
      const delta = now - screen;
      if (Math.abs(delta) < 0.01) return;
      const nudge = parseFloat(v.contentDOM.style.getPropertyValue('--nudge')) || 0;
      const wanted = nudge - delta;
      const whole = Math.floor(wanted);
      v.contentDOM.style.setProperty('--nudge', `${wanted - whole}px`);
      v.scrollDOM.scrollTop -= whole;
      if (tries > 1) hold(v, anchor, screen, tries - 1);
    },
  });
}
