import { syntaxTree } from '@codemirror/language';
import { RangeSetBuilder } from '@codemirror/state';
import { Decoration, EditorView, ViewPlugin, type DecorationSet, type ViewUpdate } from '@codemirror/view';

const blank = Decoration.line({ class: 'cm-blank' });
const quote = Decoration.line({ class: 'cm-blockquote-line' });

function within(view: EditorView, pos: number, names: RegExp) {
  let node: { name: string; parent: any } | null = syntaxTree(view.state).resolveInner(pos, 1);
  for (; node; node = node.parent) if (names.test(node.name)) return true;
  return false;
}

function build(view: EditorView): DecorationSet {
  const builder = new RangeSetBuilder<Decoration>();
  for (const { from, to } of view.visibleRanges) {
    for (let pos = from; pos <= to; ) {
      const line = view.state.doc.lineAt(pos);
      if (line.length === 0) builder.add(line.from, line.from, blank);
      else if (within(view, line.from, /^Blockquote$/)) builder.add(line.from, line.from, quote);
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
          if (u.docChanged || u.viewportChanged || syntaxTree(u.state) !== syntaxTree(u.startState)) {
            this.decorations = build(u.view);
          }
        }
      },
      { decorations: (v) => v.decorations },
    ),
    EditorView.domEventHandlers({
      mousedown(event) {
        const el = (event.target as HTMLElement).closest('.cm-wikilink') as HTMLElement | null;
        if (!el || event.button !== 0 || !el.dataset.note || el.closest('.cm-properties, .cm-embed')) return false;
        event.preventDefault();
        open(el.dataset.note);
        return true;
      },
    }),
  ];
}
