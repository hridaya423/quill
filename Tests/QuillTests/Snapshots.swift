import AppKit
import SwiftUI
import Testing
import QuillCore
@testable import Quill

@MainActor
struct Snapshots {
    nonisolated static let dir = ProcessInfo.processInfo.environment["QUILL_SNAPSHOTS"]

    static func render(_ view: NSView, _ name: String, dark: Bool) async {
        guard let dir else { return }
        view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        var shots: [(NSImage, NSRect)] = []
        for page in pages(in: view) where !page.isHiddenOrHasHiddenAncestor {
            try? await still(page)
            if let image = try? await page.takeSnapshot(configuration: nil) {
                var frame = page.convert(page.bounds, to: view)
                if view.isFlipped { frame.origin.y = view.bounds.height - frame.maxY }
                shots.append((image, frame))
            }
        }
        var out = rep
        if !shots.isEmpty, let canvas = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: rep.pixelsWide, pixelsHigh: rep.pixelsHigh, bitsPerSample: 8, samplesPerPixel: 4,
                                                        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) {
            canvas.size = rep.size
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: canvas)
            (view.appearance ?? NSAppearance(named: .aqua)!).performAsCurrentDrawingAppearance {
                Theme.paper.setFill()
                NSRect(origin: .zero, size: rep.size).fill()
            }
            for (image, frame) in shots { image.draw(in: frame) }
            rep.draw(in: NSRect(origin: .zero, size: rep.size), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: nil)
            NSGraphicsContext.restoreGraphicsState()
            out = canvas
        }
        let url = URL(fileURLWithPath: dir).appending(path: "\(name)-\(dark ? "dark" : "light").png")
        try? out.representation(using: .png, properties: [:])?.write(to: url)
    }

    static func pages(in view: NSView) -> [Page] {
        (view as? Page).map { [$0] } ?? view.subviews.flatMap(pages)
    }

    static func window(_ size: NSSize, dark: Bool) -> NSWindow {
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        return w
    }

    static func vault() throws -> URL {
        let v = FileManager.default.temporaryDirectory.appending(path: "quill-snap-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: v, withIntermediateDirectories: true)
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "../../scripts/fixtures/pitch.md")
        try FileManager.default.copyItem(at: fixture, to: v.appending(path: "pitch.md"))
        try "# Groceries\n\n- eggs\n- **oat** milk\n".write(to: v.appending(path: "Groceries.md"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: v.appending(path: "Projects/Drafts"), withIntermediateDirectories: true)
        try "# Launch plan\n\nShip on Tuesday.\n".write(to: v.appending(path: "Projects/Launch plan.md"), atomically: true, encoding: .utf8)
        try "# On revision\n\nAn essay.\n".write(to: v.appending(path: "Projects/Drafts/On revision.md"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: v.appending(path: "Journal"), withIntermediateDirectories: true)
        try "# Monday\n\nSlept well.\n".write(to: v.appending(path: "Journal/Monday.md"), atomically: true, encoding: .utf8)
        try """
        # Field notes on revision

        The first draft is for you. The second is for the reader, and it is where the work gets honest.

        ## What to cut

        - Hedges like *basically*, *kind of*, and *in a way*, which make a confident sentence sound unsure of itself.
        - Throat clearing before the point.
          - Nested: the second paragraph that repeats the first.
        1. Read it aloud.
        2. Cut a third.

        > Writing is rewriting. Every sentence earns its place or leaves.

        Use `git diff` to see what changed, or read the **whole** thing again tomorrow.

        ## This week

        - [x] Draft the [[pitch]]
        - [ ] Send it to [Sam](https://example.com) for a ==hard read==
        - [ ] Cut the ending

        ---

        ```
        swift build -c release
        ```
        """.write(to: v.appending(path: "Typography.md"), atomically: true, encoding: .utf8)
        return v
    }

    @Test(.enabled(if: dir != nil)) func states() async throws {
        Brand.register()
        for dark in [false, true] {
            let ws = Workspace(vault: try Self.vault())
            let editor = EditorController(ws: ws)
            let split = NSSplitViewController()
            let side = NSSplitViewItem(sidebarWithViewController: NSHostingController(rootView: Sidebar(ws: ws, chrome: editor.chrome)))
            side.minimumThickness = 210
            split.addSplitViewItem(side)
            split.addSplitViewItem(NSSplitViewItem(viewController: editor))
            NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            let w = Self.window(NSSize(width: 1240, height: 820), dark: dark)
            w.contentViewController = split
            w.setContentSize(NSSize(width: 1240, height: 820))
            w.backgroundColor = Theme.paper
            ws.refresh()
            if let first = ws.notes.first(where: { $0.title == "pitch" }) { ws.open(first.url) }
            editor.chrome.hinting = false

            func shot(_ name: String) async {
                try? await still(editor.text)
                try? await Task.sleep(for: .milliseconds(450))
                await Self.render(w.contentView!, name, dark: dark)
            }
            await shot("window")
            if let t = ws.notes.first(where: { $0.title == "Typography" }) {
                ws.open(t.url)
                let r = editor.text.buffer.range(of: "What to cut")
                editor.text.setSelectedRange(NSRange(location: r.location + 3, length: 0))
                await shot("type")
                _ = try? await editor.text.evaluateJavaScript("quill.view.scrollDOM.scrollTop = 1e6")
                await shot("type-end")
                _ = try? await editor.text.evaluateJavaScript("quill.view.scrollDOM.scrollTop = 0; const s = document.createElement('style'); s.id = 'open'; s.textContent = '.cm-rail .cm-rail-card { opacity: 1; transform: none } .cm-rail .cm-rail-tick { opacity: .35 }'; document.head.appendChild(s)")
                await shot("rail-open")
                _ = try? await editor.text.evaluateJavaScript("document.getElementById('open').remove()")
                ws.open(ws.notes.first(where: { $0.title == "pitch" })!.url)
            }
            editor.chrome.hinting = true
            await shot("hint")
            editor.chrome.hinting = false
            ws.phase = .listening("make the first sentence confident")
            await shot("listening")
            ws.phase = .thinking("Reading pitch.md", words: "make the first sentence confident and short")
            await shot("thinking")
            ws.live = "The opening hedges three times before it says anything. I'll cut it to one confident sentence and leave the rest"
            await shot("streaming")
            ws.live = ""
            ws.phase = .applying(3)
            await shot("applying")
            ws.phase = .done(3)
            await shot("done")
            ws.phase = .said("Tightened the opening to one confident sentence.")
            await shot("said")
            ws.phase = .said(readable("""
            <notes>[{"quote": "x", "note": "y"}]</notes>
            The draft is clear, but three things hold it back.

            - **Opening:** it hedges three times before it says anything. Lead with the claim.
            - **Middle:** the second paragraph repeats the first. Cut it or merge the one new fact.
            - **Ending:** the last line restates the title. End on what the reader can do next.

            ## Smaller things
            * "Basically" appears four times.
            * Two sentences run past forty words.
            """))
            await shot("said-long")
            ws.sources = ["Honey/edvideo/README.md", "Honey/edvideo/PLAN.md", "Honey/edvideo/docs", "Honey/edvideo/AGENTS.md", "Honey/edvideo/brand"]
                .map { URL(fileURLWithPath: NSHomeDirectory()).appending(path: $0) }
            ws.phase = .said("I drafted the LiveFrame pitch from the README and the plan.")
            await shot("said-sources")
            ws.sources = []
            editor.chrome.draft = "draft a demo pitch from @"
            editor.chrome.commanding = true
            await shot("mention")
            editor.chrome.draft = ""
            editor.chrome.commanding = false
            ws.phase = .failed("Claude Code stopped responding. Check that Node is installed, then try again.")
            await shot("failed")
            ws.phase = .idle
            editor.chrome.commanding = true
            await shot("command")
            editor.chrome.commanding = false
            editor.chrome.selectedWords = 7
            editor.chrome.commanding = true
            await shot("command-selection")
            editor.chrome.selectedWords = 0
            editor.chrome.commanding = false
            let pitch = editor.text.buffer
            let hedge = pitch.range(of: "We are basically trying to kind of build a tool that maybe helps people write better, in a way.")
            if hedge.location != NSNotFound {
                editor.text.play([Change(range: hedge, text: "We are building a tool that helps people write better.")], as: .agent(turn: 1, flags: [], by: "Codex"), turn: 1)
                await editor.text.settled()
                ws.phase = .said("Cut the hedges from the opening.")
                await shot("review")
                ws.phase = .idle
                editor.text.setSelectedRange(NSRange(location: hedge.location + 4, length: 0))
                await shot("review-card")
                ws.installed["codex"] = true
                ws.crew = ["codex", "cursor"]
                editor.chrome.commanding = true
                await shot("crew-command")
                editor.chrome.commanding = false
                ws.crew = []
                ws.revert()
                try? await Task.sleep(for: .milliseconds(200))
                let again2 = editor.text.buffer.range(of: "kind of build")
                editor.text.play([Change(range: again2, text: "build — not just a tool")], as: .agent(turn: 2, flags: ["Em dash: “—”", "Negative parallelism: “not just”"]), turn: 2)
                await editor.text.settled()
                editor.text.setSelectedRange(NSRange(location: again2.location + 2, length: 0))
                await shot("review-flagged")
                ws.revert()
                editor.text.setSelectedRange(NSRange(location: 0, length: 0))
            }
            ws.transcript[ws.current!] = [
                Line(words: "make the first sentence confident and short", reply: "Cut the hedges from the opening."),
                Line(words: "what do you think of the ending?", reply: "It lands, but the last clause repeats the title. End on the promise instead."),
            ]
            editor.chrome.commanding = true
            await shot("command-history")
            editor.chrome.commanding = false
            editor.chrome.searching = true
            await shot("search")
            editor.chrome.searching = false
            let doc = editor.text.text
            ws.margin = notes(from: """
            [{"quote": "basically trying to kind of build", "note": "Three hedges in one clause. Say what you are building."},
             {"quote": "Writers lose hours to editing", "note": "Strong. Lead with this."}]
            """, in: doc) ?? []
            await shot("notes")
            ws.margin = []
            ws.installed = ["npx": true, "codex": true, "gemini": false, "opencode": false]
            for pane in Pane.allCases {
                let settings = NSHostingView(rootView: PaneView(pane: pane, ws: ws, chrome: editor.chrome))
                settings.frame = NSRect(origin: .zero, size: settings.fittingSize)
                let sw = Self.window(settings.fittingSize, dark: dark)
                sw.contentView = settings
                try? await Task.sleep(for: .milliseconds(300))
                await Self.render(settings, "settings-\(pane.rawValue)", dark: dark)
            }
            ws.agentID = "api"
            let api = NSHostingView(rootView: PaneView(pane: .cowriters, ws: ws, chrome: editor.chrome))
            api.frame = NSRect(origin: .zero, size: api.fittingSize)
            let aw = Self.window(api.fittingSize, dark: dark)
            aw.contentView = api
            try? await Task.sleep(for: .milliseconds(300))
            await Self.render(api, "settings-api", dark: dark)
            ws.agentID = "claude"
            ws.crew = ["codex"]
            let crewPane = NSHostingView(rootView: PaneView(pane: .cowriters, ws: ws, chrome: editor.chrome))
            crewPane.frame = NSRect(origin: .zero, size: crewPane.fittingSize)
            let cw = Self.window(crewPane.fittingSize, dark: dark)
            cw.contentView = crewPane
            try? await Task.sleep(for: .milliseconds(300))
            await Self.render(crewPane, "settings-crew", dark: dark)
            ws.crew = []
            ws.current = nil
            editor.text.load("")
            ws.phase = .idle
            await shot("empty")
            if let first = ws.notes.first(where: { $0.title == "pitch" }) { ws.open(first.url) }
            w.setContentSize(NSSize(width: 680, height: 600))
            await shot("compact")
        }
    }

    @Test(.enabled(if: dir != nil)) func stage() throws {
        #expect(Stage.library != nil)
        for (dawn, name) in [(0.35, "rising"), (1.0, "dawn"), (0.62, "setup")] {
            let renderer = ImageRenderer(content: Stage(dawn: dawn, drift: 0).frame(width: 1240, height: 820))
            renderer.scale = 2
            guard let image = renderer.cgImage, let dir = Self.dir else { continue }
            let rep = NSBitmapImageRep(cgImage: image)
            try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appending(path: "stage-\(name).png"))
        }
        let pitch = ImageRenderer(content: ZStack { Stage(dawn: 0.62, drift: 220); Pitch(place: "Obsidian Vault", notes: 561) }
            .frame(width: 1000, height: 620).environment(\.colorScheme, .dark))
        pitch.scale = 2
        if let image = pitch.cgImage, let dir = Self.dir {
            try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appending(path: "stage-pitch.png"))
        }
    }

    @Test(.enabled(if: dir != nil)) func onboarding() async throws {
        Brand.register()
        for dark in [false, true] {
            let ws = Workspace(vault: try Self.vault())
            let run = Firstrunner(current: ws.vault)
            run.places = [
                Place(url: ws.vault, label: "A new Quill folder", detail: "~/Quill"),
                Place(url: URL(fileURLWithPath: NSHomeDirectory() + "/Obsidian Vault"), label: "Obsidian Vault", detail: "Obsidian vault · ~/Obsidian Vault"),
            ]
            run.chosen = run.places[1].url
            run.sentence = (text: "I think the second draft is basically better, but the ending maybe still needs a kind of sharper turn.", source: "Essay notes")
            let host = NSHostingView(rootView: Onboarding(ws: ws, run: run) { _ in }.background(Brand.night))
            host.sizingOptions = []
            let w = Self.window(NSSize(width: 1240, height: 820), dark: dark)
            w.contentView = host
            host.frame = NSRect(x: 0, y: 0, width: 1240, height: 820)
            run.count()
            if !dark {
                for (wait, name) in [(900, "a-dawn"), (900, "a-mark"), (1400, "b-word"), (2600, "c-sentence"), (1200, "d-listen"), (1000, "e-strike"), (2000, "f-kept")] {
                    try? await Task.sleep(for: .milliseconds(wait))
                    await Self.render(host, "onboard-0\(name)", dark: dark)
                }
                try? await Task.sleep(for: .milliseconds(1500))
            } else {
                run.step = .folder
                try? await Task.sleep(for: .milliseconds(1500))
            }
            run.step = .folder
            try? await Task.sleep(for: .milliseconds(800))
            await Self.render(host, "onboard-1-folder", dark: dark)
            run.lines = describe(fingerprint(["i don't know. so this is pretty much it: the thing works, mostly. we ship it tomorrow (maybe)."]))
            run.read = true
            run.step = .voice
            try? await Task.sleep(for: .milliseconds(1200))
            await Self.render(host, "onboard-2-voice", dark: dark)
            run.step = .talk
            try? await Task.sleep(for: .milliseconds(1000))
            await Self.render(host, "onboard-3-talk-idle", dark: dark)
            run.holding = true
            run.level = 0.6
            run.heard = "make the ending land harder"
            try? await Task.sleep(for: .milliseconds(1000))
            await Self.render(host, "onboard-3-talk", dark: dark)
            run.holding = false
            run.spoke = true
            ws.installed = ["npx": true, "codex": true, "gemini": false, "opencode": false]
            ws.models = [ModelChoice(id: "default", name: "Opus 4.8 (default)"), ModelChoice(id: "opus", name: "Opus 5.5")]
            ws.model = ws.models[1]
            ws.crew = ["codex"]
            run.step = .cowriter
            try? await Task.sleep(for: .milliseconds(1300))
            await Self.render(host, "onboard-4-cowriter-striking", dark: dark)
            try? await Task.sleep(for: .milliseconds(1400))
            await Self.render(host, "onboard-4-cowriter", dark: dark)
        }
    }
}
