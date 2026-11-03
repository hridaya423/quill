const base = (document.currentScript as HTMLScriptElement | null)?.src ?? location.href;
const loading = new Map<string, Promise<void>>();
const waiters = new Set<() => void>();

export type Library = 'pele' | 'katex';

export function library(name: 'pele'): PeleLib | undefined;
export function library(name: 'katex'): KatexLib | undefined;
export function library(name: Library) {
  return (window as any)[name === 'pele' ? 'Pele' : 'katex'];
}

export type PeleResult = { svg: string; width: number; height: number };
export type PeleLib = { render(source: string, options?: Record<string, unknown>): PeleResult };
export type KatexLib = { renderToString(tex: string, options?: Record<string, unknown>): string };

export function need(name: Library) {
  let promise = loading.get(name);
  if (promise) return promise;
  promise = new Promise<void>((done, fail) => {
    if (name === 'katex') {
      const css = document.createElement('link');
      css.rel = 'stylesheet';
      css.href = new URL('katex/katex.min.css', base).href;
      document.head.appendChild(css);
    }
    const script = document.createElement('script');
    script.src = new URL(`${name}.js`, base).href;
    script.onload = () => {
      done();
      for (const w of [...waiters]) w();
    };
    script.onerror = () => fail(new Error(`couldn't load ${name}`));
    document.head.appendChild(script);
  });
  loading.set(name, promise);
  return promise;
}

export function onLoaded(run: () => void) {
  waiters.add(run);
  return () => waiters.delete(run);
}
