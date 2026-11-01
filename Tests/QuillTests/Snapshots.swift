import AppKit
import SwiftUI
import Testing
import QuillCore
@testable import Quill

@MainActor
struct Snapshots {
    nonisolated static let dir = ProcessInfo.processInfo.environment["QUILL_SNAPSHOTS"]

    static func render(_ view: NSView, _ name: String, dark: Bool) {
        guard let dir else { return }
        view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        let url = URL(fileURLWithPath: dir).appending(path: "\(name)-\(dark ? "dark" : "light").png")
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
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
        """.write(to: v.appending(path: "Typography.md"), atomically: true, encoding: .utf8)
        return v
    }

    @Test(.enabled(if: dir != nil)) func states() async throws {
        for dark in [false, true] {
            let ws = Workspace(vault: try Self.vault())
            let editor = EditorController(ws: ws)
            let split = NSSplitViewController()
            let side = NSSplitViewItem(sidebarWithViewController: NSHostingController(rootView: Sidebar(ws: ws)))
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
                try? await Task.sleep(for: .milliseconds(450))
                Self.render(w.contentView!, name, dark: dark)
            }
            await shot("window")
            if let t = ws.notes.first(where: { $0.title == "Typography" }) {
                ws.open(t.url)
                let r = (editor.text.string as NSString).range(of: "What to cut")
                editor.text.setSelectedRange(NSRange(location: r.location + 3, length: 0))
                await shot("type")
                ws.open(ws.notes.first(where: { $0.title == "pitch" })!.url)
            }
            editor.chrome.hinting = true
            await shot("hint")
            editor.chrome.hinting = false
            ws.phase = .listening("make the first sentence confident")
            await shot("listening")
            ws.phase = .thinking("Reading pitch.md", words: "make the first sentence confident and short")
            await shot("thinking")
            ws.phase = .applying(3)
            await shot("applying")
            ws.phase = .done(3)
            await shot("done")
            ws.phase = .said("Tightened the opening to one confident sentence.")
            await shot("said")
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
            editor.chrome.choosingMode = true
            await shot("chooser")
            editor.chrome.choosingMode = false
            let doc = editor.text.string
            ws.margin = notes(from: """
            [{"quote": "basically trying to kind of build", "note": "Three hedges in one clause. Say what you are building."},
             {"quote": "Writers lose hours to editing", "note": "Strong. Lead with this."}]
            """, in: doc) ?? []
            await shot("notes")
            ws.margin = []
            let settings = NSHostingView(rootView: SettingsView(ws: ws))
            settings.frame = NSRect(origin: .zero, size: settings.fittingSize)
            let sw = Self.window(settings.fittingSize, dark: dark)
            sw.contentView = settings
            try? await Task.sleep(for: .milliseconds(300))
            Self.render(settings, "settings", dark: dark)
        }
    }
}
