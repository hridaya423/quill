import { EditorState, type ChangeSpec } from '@codemirror/state';
import { EditorView, drawSelection } from '@codemirror/view';
import { markdown } from '@codemirror/lang-markdown';
import { GFM } from '@lezer/markdown';
import {
  prosemarkBasicSetup,
  prosemarkBaseThemeSetup,
  prosemarkMarkdownSyntaxExtensions,
} from '@prosemark/core';

type Message =
  | { type: 'ready' }
  | { type: 'change'; changes: [number, number, string][]; anchor: number; head: number }
  | { type: 'select'; anchor: number; head: number };

const native = (window as any).webkit?.messageHandlers?.quill;
const post = (m: Message) => native?.postMessage(m);

let quiet = false;

const bridge = EditorView.updateListener.of((u) => {
  if (quiet) return;
  const { anchor, head } = u.state.selection.main;
  if (u.docChanged) {
    const changes: [number, number, string][] = [];
    u.changes.iterChanges((fromA, toA, _fromB, _toB, inserted) => {
      changes.push([fromA, toA, inserted.toString()]);
    });
    post({ type: 'change', changes, anchor, head });
  } else if (u.selectionSet) {
    post({ type: 'select', anchor, head });
  }
});

const extensions = [
  markdown({ extensions: [GFM, prosemarkMarkdownSyntaxExtensions] }),
  prosemarkBasicSetup(),
  prosemarkBaseThemeSetup(),
  drawSelection(),
  EditorView.lineWrapping,
  EditorView.contentAttributes.of({ spellcheck: 'true', autocorrect: 'on', autocapitalize: 'on' }),
  bridge,
];

const view = new EditorView({
  parent: document.getElementById('page')!,
  state: EditorState.create({ doc: '', extensions }),
});

function silently(run: () => void) {
  quiet = true;
  try { run(); } finally { quiet = false; }
}

const quill = {
  view,
  load(text: string, anchor = 0) {
    silently(() => view.setState(EditorState.create({ doc: text, extensions, selection: { anchor } })));
  },
  apply(changes: [number, number, string][]) {
    const spec: ChangeSpec[] = changes.map(([from, to, insert]) => ({ from, to, insert }));
    silently(() => view.dispatch({ changes: spec }));
  },
  select(anchor: number, head = anchor) {
    silently(() => view.dispatch({ selection: { anchor, head }, scrollIntoView: true }));
  },
  focus() { view.focus(); },
  text() { return view.state.doc.toString(); },
  bench(n = 300) {
    const times: number[] = [];
    let at = view.state.doc.length;
    for (let i = 0; i < n; i++) {
      const t = performance.now();
      view.dispatch({ changes: { from: at, insert: i % 7 === 6 ? ' ' : 'a' }, selection: { anchor: at + 1 } });
      at += 1;
      view.contentDOM.getBoundingClientRect();
      (view as any).measure?.();
      times.push(performance.now() - t);
    }
    times.sort((a, b) => a - b);
    return { p50: times[Math.floor(n / 2)], p95: times[Math.floor(n * 0.95)], max: times[n - 1] };
  },
};

(window as any).quill = quill;
post({ type: 'ready' });
