import AppKit
import Testing
@testable import Quill

@MainActor
@Suite(.serialized) struct IncrementalTests {
    static let doc = (try? String(contentsOfFile: "scripts/fixtures/obsidian/Kitchen sink.md", encoding: .utf8)) ?? ""

    static let signature = """
    window.problems = [];
    const warn = console.warn;
    console.warn = (...args) => { problems.push(args.map((a) => typeof a === 'string' ? a : JSON.stringify(a)).join(' ').slice(0, 600)); warn(...args); };
    window.addEventListener('error', (e) => problems.push(String(e.message).slice(0, 160)));
    window.signature = () => {
      const out = [];
      const walk = (n) => {
        if (n.nodeType === 3) { if (n.textContent) out.push(n.textContent); return; }
        if (n.nodeType !== 1) return;
        const el = n;
        if (el.matches('svg, .katex, .cm-cursorLayer, .cm-selectionLayer')) { out.push('<' + el.tagName + '>'); return; }
        const atom = el.matches('.cm-diagram') ? 'diagram' : el.matches('.cm-math-display') ? 'display' : el.matches('.cm-math') ? 'math' : null;
        if (atom) { out.push('<' + atom + (el.matches('.cm-diagram-editing, .cm-math-editing') ? ' editing' : '') + (el.matches('.cm-diagram-changed') ? ' changed' : '') + '>'); return; }
        out.push('<' + el.tagName + ' ' + [...el.classList].filter((c) => !/^ͼ|cm-diagram-arrive|cm-focused|cm-soft-indent-line|cm-hunk-line-fresh/.test(c)).sort().join('.') + [...el.attributes].filter((a) => a.name.startsWith('data-') || a.name.startsWith('aria-')).map((a) => ' ' + a.name + '=' + a.value).sort().join(''));
        for (const c of el.childNodes) walk(c);
        out.push('>');
      };
      walk(quill.view.contentDOM);
      return out.join('');
    };
    """

    @Test func incrementalDecorationsMatchAFullRebuild() async throws {
        let (page, window) = try await openPage(Self.doc, live: true)
        defer { window.close() }
        _ = try await page.evaluateJavaScript(Self.signature + "; true")
        try await until(6) { (try? await page.evaluateJavaScript("!!document.querySelector('.cm-diagram svg')")) as? Bool == true }
        var mismatches: [String] = []
        var steps = 0
        for round in 0..<40 {
            let result = try await page.callAsyncJavaScript("""
                let seed = \(round * 7919 + 13);
                const rand = (n) => { seed = (seed * 1103515245 + 12345) % 2147483648; return seed % n; };
                const v = quill.view;
                const bits = ['*', '**', '`', '==', '[[', ']]', '\\n', '\\n\\n', '# ', '> ', '> [!tip] ', '- [ ] ', '%%', '$', '$$', '#tag ', ' ', 'word', '```', '\\n```mermaid\\nflowchart LR\\n  A --> B\\n```\\n', '---\\n', '![[Sources]]', '<u>', '</u>', '^id', '[^1]'];
                const frame = () => new Promise((r) => requestAnimationFrame(r));
                const out = [];
                if (\(round) % 2 === 0) {
                  const m = Math.max(0, v.state.doc.toString().indexOf('```mermaid'));
                  quill.hunks([{ id: 1, from: 0, to: Math.min(200, v.state.doc.length), flagged: false }, { id: 2, from: m, to: Math.min(m + 60, v.state.doc.length), flagged: true }], null, 1e9);
                }
                for (let i = 0; i < 15; i++) {
                  const len = v.state.doc.length;
                  const at = rand(len + 1);
                  const kind = rand(5);
                  if (kind === 0 && len > 4) v.dispatch({ changes: { from: at, to: Math.min(len, at + 1 + rand(6)) }, userEvent: 'delete' });
                  else if (kind === 1) v.dispatch({ selection: { anchor: rand(len + 1) } });
                  else if (kind === 2) v.dispatch({ selection: { anchor: at, head: Math.min(len, at + rand(40)) } });
                  else v.dispatch({ changes: { from: at, insert: bits[rand(bits.length)] }, selection: { anchor: at + 1 }, userEvent: 'input.type' });
                  v.scrollDOM.scrollTop = Math.max(0, v.lineBlockAt(v.state.selection.main.head).top - 300);
                  await frame(); v.measure();
                  const before = signature();
                  quill.embeds({});
                  v.measure();
                  const after = signature();
                  if (before !== after) {
                    const at = [...before].findIndex((c, k) => c !== after[k]);
                    out.push(i + ': ' + before.slice(Math.max(0, at - 120), at + 120) + ' ≠ ' + after.slice(Math.max(0, at - 120), at + 120));
                  }
                }
                return JSON.stringify(out);
                """, contentWorld: .page) as? String ?? "[]"
            steps += 15
            let found = try JSONSerialization.jsonObject(with: Data(result.utf8)) as? [String] ?? []
            mismatches += found.map { "round \(round) step \($0)" }
            _ = try await page.evaluateJavaScript("quill.load(\(String(data: try JSONEncoder().encode(Self.doc), encoding: .utf8)!), \(round + 50)); true")
        }
        let problems = try await page.evaluateJavaScript("JSON.stringify(problems)") as? String ?? "[]"
        print("[incremental] \(steps) steps, \(mismatches.count) mismatches, problems \(problems)")
        #expect(problems == "[]")
        #expect(mismatches.isEmpty, "\(mismatches.prefix(4).joined(separator: "\n"))")
    }

    @Test func listIndentsFollowAFaceChange() async throws {
        let list = (1...6).map { "\($0). Item \($0) runs long enough to wrap onto a second line inside the column, so the hanging indent shows." }.joined(separator: "\n")
        let (page, window) = try await openPage("# List\n\n" + list + "\n", live: true)
        defer { window.close() }
        let result = try await page.callAsyncJavaScript("""
            const frame = () => new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)));
            const indent = () => [...document.querySelectorAll('.cm-soft-indent-line')].map((l) => l.style.textIndent).join(',');
            await frame();
            const sans = indent();
            quill.face('serif');
            await frame(); await frame();
            const mono = indent();
            const line = document.querySelector('.cm-soft-indent-line');
            const bullet = line.querySelector('.cm-bullet, [class*=bullet]') ?? line.firstElementChild;
            const textLeft = (() => { const r = document.createRange(); const t = [...line.childNodes].find((n) => n.nodeType === 3 && n.textContent.trim()); r.selectNodeContents(t); return r.getClientRects()[r.getClientRects().length - 1].left; })();
            return JSON.stringify({ sans, mono, wrappedLeft: Math.round(textLeft), bodyLeft: Math.round(line.getBoundingClientRect().left + parseFloat(line.style.paddingInlineStart)) });
            """, contentWorld: .page) as? String ?? ""
        let r = try JSONSerialization.jsonObject(with: Data(result.utf8)) as! [String: Any]
        #expect(r["sans"] as? String != r["mono"] as? String, "\(result)")
        #expect(abs((r["wrappedLeft"] as! Int) - (r["bodyLeft"] as! Int)) <= 1, "\(result)")
    }

    @Test func aFoldedCalloutOpensAfterTypingAboveIt() async throws {
        let (page, window) = try await openPage("intro\n\n> [!tip]- Folded\n> Hidden body line.\n\nAfter.\n", live: true)
        defer { window.close() }
        let result = try await page.callAsyncJavaScript("""
            const frame = () => new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)));
            const v = quill.view;
            await frame();
            v.dispatch({ changes: { from: 0, insert: 'more ' }, selection: { anchor: 5 }, userEvent: 'input.type' });
            await frame();
            const fold = document.querySelector('.cm-callout-fold');
            fold.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true, button: 0 }));
            await frame();
            return [document.querySelector('.cm-callout-fold')?.dataset.open, v.contentDOM.textContent.includes('Hidden body line.')].join(',');
            """, contentWorld: .page) as? String
        #expect(result == "true,true")
    }
}
