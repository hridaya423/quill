#!/usr/bin/env python3
import html
import json
import random
import sys
from pathlib import Path

run = Path(sys.argv[1])
arms = [a for a in json.loads((run / "arms.json").read_text()) if a["generic"]]
rng = random.Random()
pairs = []
for i, a in enumerate(arms):
    sides = [("quill", a["quill"]), ("generic", a["generic"])]
    rng.shuffle(sides)
    pairs.append({"n": i, "original": a["original"], "request": a["request"], "a": sides[0], "b": sides[1]})
key = {p["n"]: {"A": p["a"][0], "B": p["b"][0]} for p in pairs}
(run / "blind-key.json").write_text(json.dumps(key, indent=1))

cards = []
for p in pairs:
    cards.append(f"""
<section data-n="{p['n']}">
  <p class="meta">{p['n'] + 1} of {len(pairs)} · request: {html.escape(p['request'])}</p>
  <p class="orig">{html.escape(p['original'])}</p>
  <div class="pair">
    <button data-pick="A"><span>A</span>{html.escape(p['a'][1])}</button>
    <button data-pick="B"><span>B</span>{html.escape(p['b'][1])}</button>
  </div>
</section>""")

page = f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Which edit sounds like you?</title>
<style>
:root {{ --paper:#fbfaf7; --ink:#22211f; --soft:#75716a; --line:#e6e2da; --accent:#3d5bd9; }}
@media (prefers-color-scheme: dark) {{ :root {{ --paper:#161615; --ink:#e8e6e1; --soft:#9c988f; --line:#2c2b29; --accent:#8fa6ff; }} }}
body {{ background:var(--paper); color:var(--ink); font:17px/1.6 ui-serif, Georgia, serif; max-width:760px; margin:48px auto; padding:0 16px; }}
h1 {{ font-size:30px; margin:0 0 6px; }} .lede {{ color:var(--soft); font:14px/1.5 -apple-system, sans-serif; margin:0 0 40px; }}
section {{ border-top:1px solid var(--line); padding:28px 0; }}
.meta {{ font:12px -apple-system, sans-serif; color:var(--soft); letter-spacing:.02em; margin:0 0 10px; }}
.orig {{ color:var(--soft); font-style:italic; margin:0 0 16px; }}
.pair {{ display:grid; grid-template-columns:1fr 1fr; gap:12px; }}
@media (max-width:640px) {{ .pair {{ grid-template-columns:1fr; }} }}
button {{ all:unset; cursor:pointer; border:1px solid var(--line); border-radius:14px; padding:14px 16px; white-space:pre-wrap; transition:border-color .15s, background .15s; }}
button span {{ display:block; font:600 11px -apple-system, sans-serif; color:var(--soft); margin-bottom:6px; }}
button:hover {{ border-color:var(--soft); }} button[aria-pressed=true] {{ border-color:var(--accent); background:color-mix(in srgb, var(--accent) 8%, transparent); }}
#done {{ position:sticky; bottom:16px; background:var(--ink); color:var(--paper); font:600 14px -apple-system, sans-serif; border-radius:999px; padding:12px 18px; text-align:center; }}
</style></head><body>
<h1>Which edit sounds like you?</h1>
<p class="lede">Each card shows one of your paragraphs and two edits. Pick the one you'd keep. The labels are shuffled; the key is in blind-key.json next to this file.</p>
{''.join(cards)}
<p id="done">0 of {len(pairs)} picked</p>
<script>
const picks = {{}};
document.querySelectorAll('section').forEach(s => s.querySelectorAll('button').forEach(b => b.onclick = () => {{
  s.querySelectorAll('button').forEach(x => x.setAttribute('aria-pressed', x === b));
  picks[s.dataset.n] = b.dataset.pick;
  const n = Object.keys(picks).length;
  document.getElementById('done').textContent = n < {len(pairs)} ? `${{n}} of {len(pairs)} picked` : 'Done. Copy this to Quill: ' + JSON.stringify(picks);
}}));
</script></body></html>"""
(run / "blind.html").write_text(page)
print(run / "blind.html")
