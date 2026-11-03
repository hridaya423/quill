import AppKit
import Testing
@testable import Quill

@MainActor
@Suite(.serialized) struct ShiftTests {
    static let filler = (1...14).map { "Paragraph \($0) runs long enough to wrap across the column so the page has some real weight to it, like prose does." }.joined(separator: "\n\n")
    static let doc = """
    ---
    tags: [plan]
    status: draft
    ---
    # Shifts

    \(filler)

    ```mermaid
    flowchart TD
      A[Start] --> B[Middle]
      B --> C[End]
    ```

    After the diagram.

    $$
    \\sum_{i=1}^{n} i = \\frac{n(n+1)}{2}
    $$

    After the formula.

    > [!tip]- Folded
    > Hidden body line one.
    > Hidden body line two.

    \(filler)
    """

    static let still = 0.01

    static let probe = """
    window.probe = {
      wait: () => new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(() => requestAnimationFrame(() => requestAnimationFrame(r))))),
      top: (sel) => document.querySelector(sel).getBoundingClientRect().top,
      lineTop: (pos) => quill.view.lineBlockAt(pos).top + quill.view.documentTop,
      rect: (pos) => [...document.querySelectorAll('.cm-line')].find((l) => { try { return quill.view.state.doc.lineAt(quill.view.posAtDOM(l)).from === quill.view.state.doc.lineAt(pos).from } catch { return false } }).getBoundingClientRect().top,
      find: (text) => quill.view.state.doc.toString().indexOf(text),
      click(el, x, y) {
        const r = el.getBoundingClientRect();
        const cx = x ?? r.left + r.width / 2, cy = y ?? r.top + Math.min(r.height / 2, 12);
        const target = document.elementFromPoint(cx, cy) || el;
        for (const type of ['mousedown', 'mouseup']) target.dispatchEvent(new MouseEvent(type, { bubbles: true, cancelable: true, clientX: cx, clientY: cy, button: 0, detail: 1, view: window }));
      },
      center(pos) {
        const s = quill.view.scrollDOM;
        s.scrollTop = Math.max(0, quill.view.lineBlockAt(pos).top - s.clientHeight / 2);
      },
    };
    """

    func setup() async throws -> (Page, NSWindow) {
        let (page, window) = try await openPage(Self.doc, live: true)
        _ = try await page.evaluateJavaScript(Self.probe + "; true")
        try await until(6) { (try? await page.evaluateJavaScript("!!document.querySelector('.cm-diagram svg') && !!document.querySelector('.cm-math-display .katex')")) as? Bool == true }
        return (page, window)
    }

    func run(_ page: Page, _ body: String) async throws -> Double {
        let value = try await page.callAsyncJavaScript(body, contentWorld: .page)
        let delta = (value as? Double) ?? (value as? NSNumber)?.doubleValue ?? .nan
        print("[shift] \(delta) pt")
        return delta
    }

    @Test func clickingADiagramLeavesItWhereItWas() async throws {
        let (page, window) = try await setup()
        defer { window.close() }
        let delta = try await run(page, """
            probe.center(probe.find('```mermaid')); await probe.wait();
            const before = probe.top('.cm-diagram');
            probe.click(document.querySelector('.cm-diagram')); await probe.wait();
            if (!document.querySelector('.cm-diagram.cm-diagram-editing')) return 999;
            return probe.top('.cm-diagram') - before;
            """)
        #expect(abs(delta) <= Self.still, "moved \(delta) pt")
    }

    @Test func leavingADiagramKeepsTheClickedLineStill() async throws {
        let (page, window) = try await setup()
        defer { window.close() }
        let delta = try await run(page, """
            const pos = probe.find('After the diagram.');
            probe.center(pos); await probe.wait();
            probe.click(document.querySelector('.cm-diagram')); await probe.wait();
            if (!document.querySelector('.cm-diagram.cm-diagram-editing')) return 994;
            const line = [...document.querySelectorAll('.cm-line')].find((l) => l.textContent.startsWith('After the diagram.'));
            const before = line.getBoundingClientRect().top;
            probe.click(line); await probe.wait();
            if (document.querySelector('.cm-diagram.cm-diagram-editing')) return 998;
            return probe.rect(pos) - before;
            """)
        #expect(abs(delta) <= Self.still, "moved \(delta) pt")
    }

    @Test func arrowingIntoAFormulaLeavesItWhereItWas() async throws {
        let (page, window) = try await setup()
        defer { window.close() }
        let delta = try await run(page, """
            const pos = probe.find('After the diagram.');
            probe.center(pos); await probe.wait();
            quill.view.dispatch({ selection: { anchor: pos + 3 } }); quill.view.focus(); await probe.wait();
            const before = probe.top('.cm-math-display');
            quill.view.contentDOM.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowDown', code: 'ArrowDown', keyCode: 40, bubbles: true, cancelable: true }));
            await probe.wait(); await probe.wait();
            if (!document.querySelector('.cm-math-display.cm-math-editing')) return 997;
            return probe.top('.cm-math-display') - before;
            """)
        #expect(abs(delta) <= Self.still, "moved \(delta) pt")
    }

    @Test func aDiagramGrowingWhileYouTypeKeepsTheCaretLineStill() async throws {
        let (page, window) = try await setup()
        defer { window.close() }
        let delta = try await run(page, """
            const at = probe.find('  B --> C[End]') + '  B --> C[End]'.length;
            probe.center(at); await probe.wait();
            quill.view.dispatch({ selection: { anchor: at }, userEvent: 'select' }); await probe.wait(); await probe.wait();
            const before = probe.lineTop(at);
            quill.view.dispatch({ changes: { from: at, insert: '\\n  C --> D[After]\\n  D --> E[Further]' }, selection: { anchor: at + 34 }, userEvent: 'input.type' });
            await probe.wait(); await probe.wait();
            return probe.lineTop(at) - before;
            """)
        #expect(abs(delta) <= Self.still, "moved \(delta) pt")
    }

    @Test func leavingThePropertiesKeepsTheClickedLineStill() async throws {
        let (page, window) = try await setup()
        defer { window.close() }
        let delta = try await run(page, """
            quill.view.scrollDOM.scrollTop = 0; await probe.wait();
            probe.click(document.querySelector('.cm-properties')); await probe.wait();
            if (document.querySelector('.cm-properties')) return 996;
            const pos = probe.find('Paragraph 2 ');
            const line = [...document.querySelectorAll('.cm-line')].find((l) => l.textContent.startsWith('Paragraph 2 '));
            const before = line.getBoundingClientRect().top;
            probe.click(line); await probe.wait();
            if (!document.querySelector('.cm-properties')) return 995;
            return probe.rect(pos) - before;
            """)
        #expect(abs(delta) <= Self.still, "moved \(delta) pt")
    }

    @Test func aBrokenDiagramKeepsItsLastDrawing() async throws {
        let (page, window) = try await setup()
        defer { window.close() }
        let result = try await page.callAsyncJavaScript("""
            const at = probe.find('  B --> C[End]');
            probe.center(at); await probe.wait();
            quill.view.dispatch({ selection: { anchor: at }, userEvent: 'select' }); await probe.wait();
            const svg = document.querySelector('.cm-diagram svg').outerHTML.length;
            quill.view.dispatch({ changes: { from: at, insert: '  ]]] --> (((\\n' }, userEvent: 'input.type' });
            await probe.wait();
            const typing = { svg: !!document.querySelector('.cm-diagram svg'), stale: !!document.querySelector('.cm-diagram-stale'), note: document.querySelector('.cm-diagram-note').textContent };
            await new Promise((r) => setTimeout(r, 400));
            quill.view.dispatch({ selection: { anchor: probe.find('After the formula.') }, userEvent: 'select' });
            await probe.wait();
            const left = { svg: document.querySelector('.cm-diagram svg')?.outerHTML.length ?? 0, stale: !!document.querySelector('.cm-diagram-stale') };
            return JSON.stringify({ svg, typing, left });
            """, contentWorld: .page) as? String ?? ""
        print("[broken] \(result)")
        #expect(result.contains("\"typing\":{\"svg\":true,\"stale\":true"))
        #expect(result.contains("Showing the last version that drew."))
        #expect(result.contains("\"stale\":true}"))
        #expect(!result.contains("\"left\":{\"svg\":0"))
    }

    @Test func anUnclosedFenceNeverDraws() async throws {
        let (page, window) = try await openPage("# Draft\n\n```mermaid\nflowchart LR\n  A --> B\n\nMore text after.\n", live: true)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(500))
        let drawn = try await page.evaluateJavaScript("document.querySelectorAll('.cm-diagram').length") as? Int
        #expect(drawn == 0)
    }

    @Test func typingBesideAnEmbedThatHasNotLoaded() async throws {
        let (page, window) = try await openPage("# Draft\n\n![[Somewhere]]\n\nText ![[Inline.png]] here.\n", live: true)
        defer { window.close() }
        let shown = try await page.callAsyncJavaScript("""
            const at = quill.view.state.doc.length;
            for (let i = 0; i < 3; i++) quill.view.dispatch({ changes: { from: at + i, insert: 'a' }, userEvent: 'input.type' });
            return document.querySelectorAll('.cm-embed').length;
            """, contentWorld: .page) as? Int
        #expect(shown == 2)
    }

    @Test func everyBrokenDiagramKeepsItsOwnLastDrawing() async throws {
        let fence = { (n: Int) in "```mermaid\nflowchart LR\n  A\(n)[First \(n)] --> B\(n)[Second \(n)]\n```" }
        let (page, window) = try await openPage("# Two\n\n\(fence(1))\n\n\(fence(2))\n\n\(Self.filler)\n\n\(Self.filler)\n\nEnd.\n", live: true)
        defer { window.close() }
        try await until(6) { (try? await page.evaluateJavaScript("document.querySelectorAll('.cm-diagram svg').length === 2")) as? Bool == true }
        try await Task.sleep(for: .milliseconds(500))
        let result = try await page.callAsyncJavaScript("""
            const frame = () => new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)));
            const v = quill.view;
            v.scrollDOM.scrollTop = v.scrollDOM.scrollHeight; await frame(); await frame();
            if (document.querySelector('.cm-diagram')) return 'still mounted';
            const at = v.state.doc.toString().indexOf('  A1[First 1]');
            v.dispatch({ changes: { from: at, insert: '  ]]] --> (((\\n' }, userEvent: 'input.type' });
            v.scrollDOM.scrollTop = 0; await frame(); await frame();
            const first = document.querySelector('.cm-diagram');
            return JSON.stringify({ svg: !!first.querySelector('svg'), stale: first.classList.contains('cm-diagram-stale') });
            """, contentWorld: .page) as? String
        #expect(result == "{\"svg\":true,\"stale\":true}")
    }

    @Test func wrappedLinesHangUnderTheirText() async throws {
        let long = "runs long enough to wrap onto a second line inside the column so the hang has to show itself here."
        let doc = "# Lists\n\n- A bullet \(long)\n- [ ] A task \(long)\n1. A numbered \(long)\n\n> [!note] Callout\n> A callout \(long)\n\n> A quote \(long)\n"
        let (page, window) = try await openPage(doc, live: true)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(400))
        let result = try await page.callAsyncJavaScript("""
            const v = quill.view;
            const out = [];
            for (const name of ['A bullet', 'A task', 'A numbered', 'A callout', 'A quote']) {
                const at = v.state.doc.toString().indexOf(name);
                const line = v.state.doc.lineAt(at);
                const body = v.coordsForChar(at).left;
                const end = v.coordsAtPos(line.to, -1);
                const wrap = v.coordsForChar(v.posAtCoords({ x: v.contentDOM.getBoundingClientRect().left + 1, y: (end.top + end.bottom) / 2 })).left;
                out.push([name, Math.round((wrap - body) * 10) / 10]);
            }
            return JSON.stringify(out);
            """, contentWorld: .page) as? String ?? ""
        let rows = try JSONSerialization.jsonObject(with: Data(result.utf8)) as! [[Any]]
        #expect(rows.count == 5)
        for row in rows { #expect(abs(row[1] as! Double) <= 1, "\(result)") }
    }

    @Test func aReopenedNoteLandsWhereItWasOnTheFirstFrame() async throws {
        let (page, window) = try await openPage(Self.doc, live: true)
        defer { window.close() }
        let text = Self.doc + "\n\n" + Self.filler
        let json = String(data: try JSONEncoder().encode(text), encoding: .utf8)!
        let result = try await page.callAsyncJavaScript("""
            const v = quill.view;
            const frame = () => new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)));
            const place = () => { const s = v.scrollSnapshot().value; return [s.range.head, Math.round(s.yMargin)]; };
            quill.load(\(json), 70);
            await frame();
            v.scrollDOM.scrollTop = 2345;
            await frame();
            const saved = place();
            quill.load('# Elsewhere\\n\\nShort.', 71);
            await frame();
            quill.load(\(json), 72, 0, saved[0], saved[1]);
            v.measure();
            const first = place();
            await frame();
            return JSON.stringify({ saved, first, later: place() });
            """, contentWorld: .page) as? String ?? ""
        let r = try JSONSerialization.jsonObject(with: Data(result.utf8)) as! [String: Any]
        let saved = r["saved"] as! [Int]
        for key in ["first", "later"] {
            let got = r[key] as! [Int]
            #expect(got[0] == saved[0] && abs(got[1] - saved[1]) <= 1, "\(key): \(result)")
        }
    }
}
