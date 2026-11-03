import AppKit
import Testing
@testable import Quill

@MainActor
@Suite(.serialized) struct Bench {
    nonisolated static let file = ProcessInfo.processInfo.environment["QUILL_BENCH"]

    static let middle = """
    (() => { const d = quill.view.state.doc; let l = d.lineAt(d.length >> 1); while (l.length < 80 || /^[#>|`-]/.test(l.text)) l = d.line(l.number + 1); quill.view.dispatch({selection: {anchor: l.from + (l.length >> 1)}, scrollIntoView: true}); })()
    """

    static let loop = """
    window.typing = (n) => {
      const view = quill.view; let at = view.state.selection.main.head; const start = at;
      const begin = performance.now();
      let layout = 0, state = 0;
      for (let i = 0; i < n; i++) {
        const s0 = performance.now();
        const tr = view.state.update({ changes: { from: at, insert: i % 7 === 6 ? ' ' : 'a' }, selection: { anchor: at + 1 }, userEvent: 'input.type' });
        tr.state;
        state += performance.now() - s0;
        view.dispatch(tr);
        at += 1;
        const t = performance.now();
        view.contentDOM.getBoundingClientRect();
        layout += performance.now() - t;
      }
      const mean = (performance.now() - begin) / n;
      view.dispatch({ changes: { from: start, to: at }, selection: { anchor: start } });
      return Math.round(mean * 1000) / 1000 + '/s' + Math.round(state / n * 1000) / 1000 + '/l' + Math.round(layout / n * 1000) / 1000;
    };
    """

    @Test(.enabled(if: file != nil)) func keystrokes() async throws {
        let text = try String(contentsOfFile: Self.file!, encoding: .utf8)
        let (page, window) = try await openPage(text, live: ProcessInfo.processInfo.environment["QUILL_BENCH_OFFSCREEN"] == nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(600))
        _ = try await page.evaluateJavaScript(Self.middle + "; " + Self.loop + "; typing(60)")
        var runs: [String] = []
        for _ in 0..<5 {
            let result = try await page.evaluateJavaScript("String(typing(300))") as? String
            runs.append(result ?? "nil")
        }
        print("[bench \(text.utf16.count) chars] \(runs.joined(separator: " "))")
        let json = String(data: try JSONEncoder().encode(text), encoding: .utf8)!
        let journeys = try await page.evaluateJavaScript("""
            (() => {
              const v = quill.view, out = {};
              const time = (fn) => { const t = performance.now(); fn(); v.measure(); v.contentDOM.getBoundingClientRect(); return performance.now() - t; };
              const stats = (xs) => { xs.sort((a, b) => a - b); return { p50: +xs[xs.length >> 1].toFixed(2), max: +xs[xs.length - 1].toFixed(2) }; };
              const moves = [];
              const h0 = v.state.selection.main.head;
              out.first = [time(() => v.state.update({ selection: { anchor: h0 + 1 } }).state), time(() => v.dispatch({ selection: { anchor: h0 + 1 } })), time(() => v.dispatch({ selection: { anchor: h0 + 2 }, userEvent: 'select' })), time(() => v.dispatch({ selection: { anchor: h0 + 3 }, userEvent: 'select', scrollIntoView: true }))].map((x) => +x.toFixed(1));
              for (let i = 0; i < 120; i++) {
                const head = v.state.selection.main.head;
                const line = v.state.doc.lineAt(head);
                const next = line.number < v.state.doc.lines ? v.state.doc.line(line.number + 1) : v.state.doc.line(1);
                const t0 = performance.now();
                const tr = v.state.update({ selection: { anchor: Math.min(next.to, next.from + (head - line.from)) }, userEvent: 'select', scrollIntoView: true });
                tr.state;
                const t1 = performance.now();
                v.dispatch(tr);
                const t2 = performance.now();
                v.measure(); v.contentDOM.getBoundingClientRect();
                const ms = performance.now() - t0;
                (out.parts ??= [0, 0, 0]); out.parts[0] += t1 - t0; out.parts[1] += t2 - t1; out.parts[2] += performance.now() - t2;
                moves.push(ms);
                if (ms > 8) (out.slow ??= []).push([+ms.toFixed(1), next.number, next.text.slice(0, 40)]);
              }
              out.arrow = stats(moves);
              const loads = [];
              for (let i = 0; i < 6; i++) loads.push(time(() => quill.load(\(json), 900 + i)));
              out.open = stats(loads);
              const steps = [];
              v.scrollDOM.scrollTop = 0; v.measure();
              for (let y = 0; y < Math.min(v.scrollDOM.scrollHeight, 60000); y += 300) steps.push(time(() => { v.scrollDOM.scrollTop = y; }));
              out.scroll = stats(steps);
              const fine = [];
              v.scrollDOM.scrollTop = 0; v.measure();
              for (let y = 0; y < Math.min(v.scrollDOM.scrollHeight, 60000); y += 40) fine.push(time(() => { v.scrollDOM.scrollTop = y; }));
              out.scroll40 = stats(fine);
              const sorted = [...steps].sort((a, b) => a - b); out.scrollP95 = +sorted[Math.floor(sorted.length * 0.95)].toFixed(2);
              return JSON.stringify(out);
            })()
            """) as? String ?? ""
        print("[journeys] \(journeys)")
    }
}

@MainActor
@Suite(.serialized) struct Frames {
    nonisolated static let on = ProcessInfo.processInfo.environment["QUILL_FRAMES"] != nil
    nonisolated static let examples = ProcessInfo.processInfo.environment["QUILL_EXAMPLES"]

    static let note: String = (1...20).map { i in
        """
        ## Part \(i)

        Paragraph \(i) runs long enough to wrap across the column so the page has some real weight to it, like prose does. It keeps going for a second sentence.

        ```mermaid
        flowchart LR
          A\(i)[Input \(i)] --> B\(i){Check}
          B\(i) -->|yes| C\(i)[Store]
          B\(i) -->|no| D\(i)[Retry]
          D\(i) --> A\(i)
          C\(i) --> E\(i)[(Database)]
        ```

        After diagram \(i).
        """
    }.joined(separator: "\n\n")

    static let probe = """
    window.frames = {
      cost(fn) { const t = performance.now(); fn(); quill.view.measure(); document.body.getBoundingClientRect(); return performance.now() - t; },
      stats(xs) { const s = [...xs].sort((a, b) => a - b); return { n: s.length, p50: +s[s.length >> 1].toFixed(2), p95: +s[Math.floor(s.length * 0.95)].toFixed(2), max: +s[s.length - 1].toFixed(2) }; },
      toggles() {
        const v = quill.view, text = v.state.doc.toString(), enter = [], leave = [];
        let at = 0;
        for (;;) {
          const fence = text.indexOf('```mermaid', at);
          if (fence < 0) break;
          const after = text.indexOf('After diagram', fence);
          v.dispatch({ effects: quill.view.constructor.scrollIntoView(fence, { y: 'center' }) }); v.measure();
          enter.push(this.cost(() => v.dispatch({ selection: { anchor: fence + 12 }, userEvent: 'select.pointer' })));
          leave.push(this.cost(() => v.dispatch({ selection: { anchor: after + 2 }, userEvent: 'select.pointer' })));
          at = after;
        }
        return { enter: this.stats(enter), leave: this.stats(leave) };
      },
      scroll() {
        const v = quill.view, s = v.scrollDOM, steps = [];
        s.scrollTop = 0; v.measure();
        for (let y = 0; y < s.scrollHeight - s.clientHeight; y += 50) steps.push(this.cost(() => { s.scrollTop = y; }));
        return this.stats(steps);
      },
      async live() {
        const v = quill.view, s = v.scrollDOM, gaps = [];
        s.scrollTop = 0;
        let last = await new Promise(requestAnimationFrame);
        while (s.scrollTop < s.scrollHeight - s.clientHeight - 1) {
          s.scrollTop += 40;
          const now = await new Promise(requestAnimationFrame);
          gaps.push(now - last); last = now;
        }
        return this.stats(gaps);
      },
    };
    """

    @Test(.enabled(if: on)) func diagrams() async throws {
        let (page, window) = try await openPage(Self.note, live: true)
        defer { window.close() }
        try await until(8) { (try? await page.evaluateJavaScript("document.querySelectorAll('.cm-diagram svg').length > 0")) as? Bool == true }
        _ = try await page.evaluateJavaScript("" + Self.probe + "; true")
        _ = try await page.evaluateJavaScript("frames.toggles(); frames.scroll(); true")
        for _ in 0..<2 {
            let toggles = try await page.evaluateJavaScript("JSON.stringify(frames.toggles())") as? String ?? "nil"
            let scroll = try await page.evaluateJavaScript("JSON.stringify(frames.scroll())") as? String ?? "nil"
            print("[frames] toggles \(toggles) scroll \(scroll)")
        }
        if ProcessInfo.processInfo.environment["QUILL_ONSCREEN"] != nil {
            let live = try await page.callAsyncJavaScript("return JSON.stringify(await frames.live())", contentWorld: .page) as? String ?? "nil"
            print("[frames] live rAF gaps \(live)")
        }
    }

    @Test(.enabled(if: examples != nil)) func mermaidDocs() async throws {
        let (page, window) = try await openPage("```mermaid\nflowchart LR\n  A --> B\n```\n")
        defer { window.close() }
        try await until(8) { (try? await page.evaluateJavaScript("!!window.Pele")) as? Bool == true }
        let json = try String(contentsOfFile: Self.examples!, encoding: .utf8)
        let result = try await page.evaluateJavaScript("""
            (() => { const out = []; let ok = 0;
              for (const e of \(json)) { try { const r = Pele.render(e.source, { idPrefix: 'x' }); if (!r.svg) throw new Error('empty'); ok++; } catch (err) { out.push(e.file + '#' + e.index + ' ' + String(err && err.message || err).slice(0, 80)); } }
              return JSON.stringify({ ok, failed: out }); })()
            """) as? String ?? "nil"
        print("[mermaid] \(result)")
    }
}

@MainActor
@Suite(.serialized) struct OpenBench {
    nonisolated static let root = ProcessInfo.processInfo.environment["QUILL_OPEN_ROOT"]
    nonisolated static let note = ProcessInfo.processInfo.environment["QUILL_OPEN_NOTE"]

    @Test(.enabled(if: root != nil && note != nil)) func openingANote() async throws {
        let ws = Workspace(vault: URL(fileURLWithPath: Self.root!), home: false)
        let (page, window) = try await openPage("", live: true)
        defer { window.close(); ws.quit() }
        ws.attach(page)
        ws.refresh()
        let note = URL(fileURLWithPath: Self.note!)
        let other = ws.notes.first { $0.url != note }!.url
        var times: [Double] = []
        for i in 0..<6 {
            let target = i.isMultiple(of: 2) ? note : other
            let start = Date()
            ws.open(target)
            times.append(Date().timeIntervalSince(start) * 1000)
        }
        print("[open] \(ws.notes.count) notes, \(Embeds.targets(in: try String(contentsOf: note, encoding: .utf8)).count) embeds: \(times.map { String(format: "%.1f", $0) }.joined(separator: " ")) ms")
    }
}
