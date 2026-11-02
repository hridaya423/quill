import { StateEffect } from '@codemirror/state';

export type Edit = [number, number, string];
export type Step = { token: number; dir: 1 | -1; group?: number };

const native = (window as any).webkit?.messageHandlers?.quill;

export const post = (m: Record<string, unknown>) => native?.postMessage(m);

export const step = StateEffect.define<Step>();

export const still = () => matchMedia('(prefers-reduced-motion: reduce)').matches;

export function place(el: HTMLElement, left: number, top: number) {
  el.style.transform = `translate(${Math.round(left)}px, ${Math.round(top)}px)`;
}

export function local(scroller: HTMLElement, rect: { left: number; top: number }) {
  const box = scroller.getBoundingClientRect();
  return { left: rect.left - box.left + scroller.scrollLeft, top: rect.top - box.top + scroller.scrollTop };
}
