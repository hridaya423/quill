import { syntaxTree } from '@codemirror/language';
import { RangeSetBuilder } from '@codemirror/state';
import { Decoration, EditorView, ViewPlugin, type DecorationSet, type ViewUpdate } from '@codemirror/view';

const pattern = /\[\[([^\[\]\n|]+)(?:\|([^\[\]\n]+))?\]\]/g;
const hidden = Decoration.replace({});
const blank = Decoration.line({ class: 'cm-blank' });
const quote = Decoration.line({ class: 'cm-blockquote-line' });

function within(view: EditorView, pos: number, names: RegExp) {
  let node: { name: string; parent: any } | null = syntaxTree(view.state).resolveInner(pos, 1);
  for (; node; node = node.parent) if (names.test(node.name)) return true;
  return false;
}

function build(view: EditorView): DecorationSet {
  const builder = new RangeSetBuilder<Decoration>();
  const caretLines = new Set(view.state.selection.ranges.map((r) => view.state.doc.lineAt(r.head).number));
  for (const { from, to } of view.visibleRanges) {
    for (let pos = from; pos <= to; ) {
      const line = view.state.doc.lineAt(pos);
      if (line.length === 0) {
        builder.add(line.from, line.from, blank);
      } else {
        if (within(view, line.from, /^Blockquote$/)) builder.add(line.from, line.from, quote);
        const marks: [number, number, Decoration][] = [];
        for (const m of line.text.matchAll(pattern)) {
          const start = line.from + m.index!;
          const end = start + m[0].length;
          if (within(view, start, /Code|Fence/)) continue;
          const target = m[1].trim();
          const link = Decoration.mark({ class: 'cm-wikilink', attributes: { 'data-note': target } });
          if (caretLines.has(line.number)) {
            marks.push([start, end, Decoration.mark({ class: 'cm-wikilink-source', attributes: { 'data-note': target } })]);
          } else {
            const labelStart = m[2] ? start + 2 + m[1].length + 1 : start + 2;
            marks.push([start, labelStart, hidden], [labelStart, end - 2, link], [end - 2, end, hidden]);
          }
        }
        for (const [a, b, d] of marks) builder.add(a, b, d);
      }
      pos = line.to + 1;
    }
  }
  return builder.finish();
}

export function ornaments(open: (note: string) => void) {
  return [
    ViewPlugin.fromClass(
      class {
        decorations: DecorationSet;
        constructor(view: EditorView) { this.decorations = build(view); }
        update(u: ViewUpdate) {
          if (u.docChanged || u.viewportChanged || u.selectionSet || syntaxTree(u.state) !== syntaxTree(u.startState)) {
            this.decorations = build(u.view);
          }
        }
      },
      { decorations: (v) => v.decorations },
    ),
    EditorView.domEventHandlers({
      mousedown(event) {
        const el = (event.target as HTMLElement).closest('.cm-wikilink');
        if (!el || event.button !== 0) return false;
        event.preventDefault();
        open(el.getAttribute('data-note')!);
        return true;
      },
    }),
  ];
}
