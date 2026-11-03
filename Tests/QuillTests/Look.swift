import AppKit
import Testing
@testable import Quill

@MainActor
func openNote(_ url: URL, root: URL, dark: Bool = false, height: CGFloat = 1000) async throws -> (Page, NSWindow) {
    let page = Page()
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: height), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    window.contentView = page
    NSApplication.shared.setActivationPolicy(.accessory)
    window.orderFront(nil)
    window.setFrameOrigin(NSPoint(x: -6000, y: 200))
    Files.roots.insert(root.standardizedFileURL.path)
    let notes = (FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? [])
        .filter { $0.pathExtension == "md" }.map { Note(url: $0, modified: .now) }
    page.onEmbed = { [weak page] target in page?.embeds([target: Embeds.payload(target, from: url, root: root, notes: notes)]) }
    try await until { page.ready }
    let text = try String(contentsOf: url, encoding: .utf8)
    var found: [String: [String: Any]] = [:]
    for target in Embeds.targets(in: text) { found[target] = Embeds.payload(target, from: url, root: root, notes: notes) }
    page.embeds(found, early: true)
    page.load(text)
    try await Task.sleep(for: .milliseconds(900))
    return (page, window)
}

@MainActor
func shoot(_ page: Page, _ path: String) async throws {
    let image = try await page.takeSnapshot(configuration: nil)
    let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
    try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

@MainActor
@Suite(.serialized) struct Look {
    nonisolated static let file = ProcessInfo.processInfo.environment["QUILL_LOOK"]
    nonisolated static let out = ProcessInfo.processInfo.environment["QUILL_SHOTS"]

    @Test(.enabled(if: file != nil && out != nil)) func note() async throws {
        let url = URL(fileURLWithPath: Self.file!)
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["QUILL_ROOT"] ?? url.deletingLastPathComponent().path)
        let name = url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: " ", with: "-")
        for dark in [false, true] {
            let (page, window) = try await openNote(url, root: root, dark: dark)
            let caret = Int(ProcessInfo.processInfo.environment["QUILL_CARET"] ?? "")
            if let caret { page.setSelectedRange(NSRange(location: caret, length: 0)); try await Task.sleep(for: .milliseconds(300)) }
            let pages = Int(ProcessInfo.processInfo.environment["QUILL_PAGES"] ?? "1") ?? 1
            for i in 0..<pages {
                _ = try await page.evaluateJavaScript("quill.view.scrollDOM.scrollTop = \(i) * 900")
                try await Task.sleep(for: .milliseconds(400))
                try await shoot(page, "\(Self.out!)/\(name)-\(dark ? "dark" : "light")-\(i).png")
            }
            window.close()
        }
    }
}

@MainActor
@Suite(.serialized) struct Audit {
    nonisolated static let root = ProcessInfo.processInfo.environment["QUILL_AUDIT"]

    @Test(.enabled(if: root != nil)) func everyPage() async throws {
        let root = URL(fileURLWithPath: Self.root!)
        let out = URL(fileURLWithPath: ProcessInfo.processInfo.environment["QUILL_AUDIT_OUT"] ?? NSTemporaryDirectory() + "audit.jsonl")
        Files.roots.insert(root.standardizedFileURL.path)
        let files = (FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? [])
            .filter { $0.pathExtension == "md" }.sorted { $0.path < $1.path }
        let notes = files.map { Note(url: $0, modified: .now) }
        let page = Page()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 1000), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = page
        NSApplication.shared.setActivationPolicy(.accessory)
        window.orderFront(nil)
        window.setFrameOrigin(NSPoint(x: -6000, y: 200))
        defer { window.close() }
        try await until { page.ready }
        var current = files[0]
        page.onEmbed = { [weak page] target in page?.embeds([target: Embeds.payload(target, from: current, root: root, notes: notes)]) }
        var lines: [String] = []
        var dirty = 0
        for file in files {
            current = file
            let text = (try String(contentsOf: file, encoding: .utf8)) + "\n\n"
            var found: [String: [String: Any]] = [:]
            for target in Embeds.targets(in: text) { found[target] = Embeds.payload(target, from: file, root: root, notes: notes) }
            page.embeds(found, early: true)
            page.load(text, caret: (text as NSString).length)
            try await Task.sleep(for: .milliseconds(350))
            let result = try await page.callAsyncJavaScript("return quill.audit()", contentWorld: .page) as? String ?? "{}"
            let rel = String(file.path.dropFirst(root.path.count + 1))
            lines.append("{\"page\": \(String(data: try JSONEncoder().encode(rel), encoding: .utf8)!), \"result\": \(result)}")
            if result.contains("\"kind\"") { dirty += 1 }
        }
        try lines.joined(separator: "\n").write(to: out, atomically: true, encoding: .utf8)
        print("[audit] \(files.count) pages, \(dirty) with raw syntax → \(out.path)")
    }
}

@MainActor
@Suite(.serialized) struct Chrome {
    nonisolated static let root = ProcessInfo.processInfo.environment["QUILL_DESK"]

    @Test(.enabled(if: root != nil && Look.out != nil)) func folderWindow() async throws {
        let root = URL(fileURLWithPath: Self.root!)
        let note = URL(fileURLWithPath: ProcessInfo.processInfo.environment["QUILL_DESK_NOTE"] ?? root.appending(path: "README.md").path)
        for dark in [false, true] {
            let desk = Desk(root: root, home: false, cascadeFrom: nil) { _ in }
            desk.window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            desk.window.setFrameOrigin(NSPoint(x: -6000, y: 200))
            desk.window.orderFront(nil)
            desk.ws.start()
            desk.ws.open(note)
            try await Task.sleep(for: .seconds(2))
            let frame = desk.window.contentView!.superview!
            let rep = frame.bitmapImageRepForCachingDisplay(in: frame.bounds)!
            frame.cacheDisplay(in: frame.bounds, to: rep)
            try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(Look.out!)/desk-\(dark ? "dark" : "light").png"))
            desk.window.close()
        }
    }
}

@MainActor
struct RoundTrip {
    @Test func typingSendsNothingBackWhenNothingIsUnderReview() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "quill-trip-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let note = root.appending(path: "draft.md")
        try "# Draft\n\nSome words to start with.\n".write(to: note, atomically: true, encoding: .utf8)
        let desk = Desk(root: root, home: false, cascadeFrom: nil) { _ in }
        desk.window.setFrameOrigin(NSPoint(x: -6000, y: 200))
        desk.window.orderFront(nil)
        defer { desk.ws.quit(); desk.window.close() }
        desk.ws.start()
        desk.ws.open(note)
        let page = try #require(desk.editor.text)
        try await until(6) { page.ready && page.text.contains("Some words") }
        let typeOne = "(() => { const v = quill.view, at = v.state.doc.length - 1; v.dispatch({ changes: { from: at, insert: 'a' }, selection: { anchor: at + 1 }, userEvent: 'input.type' }); return true; })()"
        _ = try await page.evaluateJavaScript(typeOne)
        try await Task.sleep(for: .milliseconds(300))
        _ = try await page.evaluateJavaScript("""
            window.calls = {};
            for (const name of ['hunks', 'notes', 'card']) { const f = quill[name]; quill[name] = (...a) => { calls[name] = (calls[name] ?? 0) + 1; return f(...a); }; }
            true
            """)
        for _ in 0..<50 { _ = try await page.evaluateJavaScript(typeOne) }
        try await Task.sleep(for: .milliseconds(400))
        let calls = try await page.evaluateJavaScript("JSON.stringify(calls)") as? String
        #expect(calls == "{}", "\(calls ?? "")")
    }
}
