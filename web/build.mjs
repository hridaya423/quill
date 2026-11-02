import { build } from 'esbuild';
import { copyFileSync, mkdirSync } from 'node:fs';

const out = '../Sources/Quill/Brand/Editor';
mkdirSync(out, { recursive: true });
await build({
  entryPoints: ['src/main.ts'],
  bundle: true,
  minify: true,
  format: 'iife',
  target: 'safari18',
  outfile: `${out}/editor.js`,
  legalComments: 'none',
});
copyFileSync('src/page.css', `${out}/page.css`);
copyFileSync('src/index.html', `${out}/index.html`);
