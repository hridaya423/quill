import { build } from 'esbuild';
import { copyFileSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { patches } from './patches/prosemark.mjs';

const prosemark = {
  name: 'prosemark',
  setup(b) {
    b.onLoad({ filter: /@prosemark[\\/]core[\\/]dist[\\/]main\.js$/ }, ({ path }) => {
      let text = readFileSync(path, 'utf8');
      for (const [from, to] of patches) {
        if (text.split(from).length !== 2) throw new Error(`prosemark patch no longer matches: ${from.slice(0, 60)}`);
        text = text.replace(from, () => to);
      }
      const helper = resolve('src/incremental.ts');
      return { contents: `import { incremental as __incremental, outside as __outside } from ${JSON.stringify(helper)};\n${text}`, loader: 'js', resolveDir: dirname(path) };
    });
  },
};

const out = '../Sources/Quill/Brand/Editor';
mkdirSync(out, { recursive: true });
const common = { bundle: true, minify: true, format: 'iife', target: 'safari18', legalComments: 'none' };
await build({ ...common, entryPoints: ['src/main.ts'], outfile: `${out}/editor.js`, plugins: [prosemark] });
await build({ ...common, entryPoints: ['src/pele.ts'], outfile: `${out}/pele.js` });
await build({ ...common, entryPoints: ['src/katex.ts'], outfile: `${out}/katex.js` });
copyFileSync('src/page.css', `${out}/page.css`);
copyFileSync('src/index.html', `${out}/index.html`);
mkdirSync(`${out}/katex/fonts`, { recursive: true });
const katex = 'node_modules/katex/dist';
const css = readFileSync(`${katex}/katex.min.css`, 'utf8').replace(/,url\(fonts\/[^)]+\.(woff|ttf)\) format\("(woff|truetype)"\)/g, '');
writeFileSync(`${out}/katex/katex.min.css`, css);
for (const f of readdirSync(`${katex}/fonts`).filter((f) => f.endsWith('.woff2'))) copyFileSync(`${katex}/fonts/${f}`, `${out}/katex/fonts/${f}`);
