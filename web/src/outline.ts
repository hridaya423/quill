import { syntaxTree } from '@codemirror/language';
import type { EditorState } from '@codemirror/state';
import { EditorView, ViewPlugin, type ViewUpdate } from '@codemirror/view';
import { still } from './bridge';

type Heading = { from: number; level: number; title: string };

function headings(state: EditorState): Heading[] {
  const tree = syntaxTree(state);
  const found: Heading[] = [];
  tree.iterate({
    enter(node) {
      if (node.name === 'Paragraph' || node.name === 'FencedCode' || node.name === 'CodeBlock') return false;
      const level = /^(?:ATX|Setext)Heading(\d)$/.exec(node.name)?.[1];
      if (!level) return;
      const line = state.doc.lineAt(node.from);
      const title = line.text.replace(/^\s*#{1,6}\s*/, '').replace(/\s+#+\s*$/, '').trim();
      if (title) found.push({ from: line.from, level: Number(level), title });
      return false;
    },
  });
  const shallow = found.filter((h) => h.level <= 3);
  return shallow.length > 32 ? shallow.filter((h) => h.level <= 2) : shallow;
}

const same = (a: Heading[], b: Heading[]) =>
  a.length === b.length && a.every((h, i) => h.from === b[i].from && h.level === b[i].level && h.title === b[i].title);

export const outline = ViewPlugin.fromClass(
  class {
    shown: Heading[] = [];
    current = -1;
    timer = 0;
    frame = 0;
    dom = document.createElement('nav');
    ticks = document.createElement('div');
    card = document.createElement('div');
    locate = () => {
      if (!this.frame) this.place();
    };
    halt = () => {
      cancelAnimationFrame(this.frame);
      this.frame = 0;
    };

    constructor(readonly view: EditorView) {
      this.dom.className = 'cm-rail';
      this.dom.setAttribute('aria-label', 'Outline');
      this.ticks.className = 'cm-rail-ticks';
      this.ticks.setAttribute('aria-hidden', 'true');
      this.card.className = 'cm-rail-card';
      this.dom.append(this.ticks, this.card);
      this.dom.addEventListener('mousedown', (e) => e.preventDefault());
      view.dom.appendChild(this.dom);
      view.scrollDOM.addEventListener('scroll', this.locate, { passive: true });
      view.scrollDOM.addEventListener('wheel', this.halt, { passive: true });
      this.refresh();
    }

    update(u: ViewUpdate) {
      if (u.docChanged) {
        clearTimeout(this.timer);
        this.timer = window.setTimeout(() => this.refresh(), 150);
      } else if (syntaxTree(u.startState) !== syntaxTree(u.state)) {
        this.refresh();
      } else if (u.geometryChanged) {
        this.measure();
      }
    }

    refresh() {
      const next = headings(this.view.state);
      if (!same(next, this.shown)) {
        this.shown = next;
        this.current = -1;
        this.ticks.replaceChildren(
          ...next.map((h) => {
            const tick = document.createElement('div');
            tick.className = 'cm-rail-tick';
            tick.dataset.level = String(h.level);
            return tick;
          }),
        );
        this.card.replaceChildren(
          ...next.map((h, i) => {
            const row = document.createElement('button');
            row.className = 'cm-rail-row';
            row.dataset.level = String(h.level);
            row.textContent = h.title;
            row.title = h.title;
            row.addEventListener('click', () => this.jump(i));
            return row;
          }),
        );
        this.dom.hidden = next.length < 2;
      }
      this.measure();
    }

    measure() {
      this.view.requestMeasure({ key: this, read: () => this.read(), write: (index) => this.mark(index) });
    }

    place() {
      this.mark(this.read());
    }

    read() {
      const { shown, view } = this;
      const s = view.scrollDOM;
      if (shown.length < 2 || s.scrollTop <= 0) return 0;
      if (s.scrollTop + s.clientHeight >= s.scrollHeight - 4) return shown.length - 1;
      const y = s.getBoundingClientRect().top + 96 - view.documentTop;
      const pos = view.lineBlockAtHeight(Math.max(0, y)).from;
      return Math.max(0, shown.findLastIndex((h) => h.from <= pos));
    }

    mark(index: number) {
      if (index === this.current) return;
      this.ticks.children[this.current]?.classList.remove('cm-rail-on');
      this.card.children[this.current]?.classList.remove('cm-rail-on');
      this.current = index;
      this.ticks.children[index]?.classList.add('cm-rail-on');
      const row = this.card.children[index] as HTMLElement | undefined;
      if (!row) return;
      row.classList.add('cm-rail-on');
      if (!this.dom.matches(':hover')) this.card.scrollTop = row.offsetTop - (this.card.clientHeight - row.offsetHeight) / 2;
    }

    jump(index: number) {
      const { view } = this;
      const line = view.state.doc.lineAt(this.shown[index].from);
      view.dispatch({ selection: { anchor: line.to }, userEvent: 'select' });
      view.focus();
      this.mark(index);
      this.halt();
      if (still() || document.hidden) {
        view.dispatch({ effects: EditorView.scrollIntoView(line.from, { y: 'start', yMargin: 64 }) });
        return;
      }
      const s = view.scrollDOM;
      const start = performance.now();
      const glide = () => {
        const target = view.lineBlockAt(line.from).top + view.documentTop - s.getBoundingClientRect().top - 64;
        const room = s.scrollHeight - s.clientHeight - s.scrollTop;
        const delta = Math.max(-s.scrollTop, Math.min(room, target));
        if (Math.abs(delta) < 1 || performance.now() - start > 1500) {
          s.scrollTop += delta;
          this.frame = 0;
          return;
        }
        s.scrollTop += delta * 0.2;
        this.frame = requestAnimationFrame(glide);
      };
      this.frame = requestAnimationFrame(glide);
    }

    destroy() {
      clearTimeout(this.timer);
      this.halt();
      this.view.scrollDOM.removeEventListener('scroll', this.locate);
      this.view.scrollDOM.removeEventListener('wheel', this.halt);
      this.dom.remove();
    }
  },
);
