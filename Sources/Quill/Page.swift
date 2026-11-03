import AppKit
import QuillCore
import WebKit

enum EditSource {
    case agent(turn: Int, flags: [String], by: String? = nil)
    case other
}

@MainActor
final class Page: WKWebView {
    private(set) var buffer = NSMutableString()
    private var selection = NSRange()
    private(set) var ready = false
    private var queued: [String] = []
    private var generation = 0
    private(set) var version = 0
    private(set) var review = Review()
    private var steps: [Int: (name: String, before: Review, after: Review)] = [:]
    private var tokens = 0
    private(set) var isPlaying = false
    private var crossed: [Hunk] = []
    private(set) var top = 0
    private(set) var shift: CGFloat = 0

    var focused: Int? {
        didSet { if focused != oldValue { pushHunks() } }
    }
    var onEdit: (() -> Void)?
    var onLoad: (() -> Void)?
    var onCaret: (() -> Void)?
    var onReview: (() -> Void)?
    var onResolve: (([Hunk], Outcome) -> Void)?
    var onUndo: ((String, Bool) -> Void)?
    var onHover: ((Int?) -> Void)?
    var onOpenNote: ((String) -> Void)?
    var onPlayed: ((Int) -> Void)?
    var onKeep: ((Int) -> Void)?
    var onRevert: ((Int) -> Void)?
    var onCardHover: ((Bool) -> Void)?
    var onApplyNote: ((Int) -> Void)?
    var onDismissNote: ((Int) -> Void)?
    var onNoteHover: ((Int?) -> Void)?
    var onEmbed: ((String) -> Void)?
    var editable = true {
        didSet { if editable != oldValue { call("quill.editable(\(editable))") } }
    }

    init() {
        let config = WKWebViewConfiguration()
        config.suppressesIncrementalRendering = true
        config.setURLSchemeHandler(Files(), forURLScheme: Files.scheme)
        super.init(frame: .zero, configuration: config)
        config.userContentController.add(Relay(self), name: "quill")
        setValue(false, forKey: "drawsBackground")
        allowsMagnification = false
        navigationDelegate = self
        if let editor = Brand.url("Editor") {
            loadFileURL(editor.appending(path: "index.html"), allowingReadAccessTo: editor.deletingLastPathComponent())
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    var text: String { buffer as String }

    func selectedRange() -> NSRange { selection }

    func embeds(_ found: [String: [String: Any]], early: Bool = false) {
        guard !found.isEmpty else { return }
        call("quill.embeds(\(json(found)), \(early))")
    }

    func load(_ text: String, caret: Int = 0, top: Int = 0, shift: CGFloat = 0) {
        generation += 1
        buffer = NSMutableString(string: text)
        selection = NSRange(location: min(caret, buffer.length), length: 0)
        version = 0
        review = Review()
        steps = [:]
        crossed = []
        focused = nil
        isPlaying = false
        self.top = top
        self.shift = shift
        sent = [:]
        call("quill.load(\(json(text)), \(generation), \(selection.location), \(top), \(shift))")
        onReview?()
        onLoad?()
    }

    func setSelectedRange(_ range: NSRange) {
        selection = range
        call("quill.select(\(range.location), \(NSMaxRange(range)), \(version))")
    }

    func focus() {
        window?.makeFirstResponder(self)
        call("quill.focus()")
    }

    func face(_ name: String) {
        call("quill.face(\(json(name)))")
    }

    func paragraph(at location: Int) -> NSRange {
        buffer.paragraphRange(for: NSRange(location: min(location, buffer.length), length: 0))
    }

    func reveal(_ range: NSRange) {
        call("quill.reveal(\(range.location), \(version))")
    }

    func present(_ range: NSRange?) {
        guard let range else { return call("quill.present(null, 0, \(version))") }
        call("quill.present(\(range.location), \(NSMaxRange(range)), \(version))")
    }

    func sweep() {
        call("quill.sweep()")
    }

    func titles(_ list: [String]) {
        call("quill.titles(\(json(list)))")
    }

    func card(_ hunk: Hunk?) {
        guard let hunk else { return once("card", "quill.card(null, 0)") }
        let spec: [String: Any] = ["id": hunk.id, "from": hunk.range.location, "to": NSMaxRange(hunk.range), "old": hunk.old, "flags": hunk.flags, "by": hunk.by ?? NSNull()]
        once("card", "quill.card(\(json(spec)), \(version))")
    }

    func notes(_ list: [MarginNote], active: Int?, busy: Bool) {
        let specs = list.filter { NSMaxRange($0.range) <= buffer.length }.map { note -> [String: Any] in
            ["id": note.id, "from": note.range.location, "to": NSMaxRange(note.range), "lens": note.lens ?? NSNull(), "note": note.note]
        }
        let script = specs.isEmpty ? "quill.notes([], \(active.map(String.init) ?? "null"), \(busy), 0)" : "quill.notes(\(json(specs)), \(active.map(String.init) ?? "null"), \(busy), \(version))"
        once("notes", script)
    }

    private var sent: [String: String] = [:]
    private func once(_ key: String, _ script: String) {
        guard sent[key] != script else { return }
        sent[key] = script
        call(script)
    }

    func setReview(_ next: Review) {
        review = next
        pushHunks()
        onReview?()
    }

    func play(_ changes: [Change], as source: EditSource, turn: Int) {
        guard !changes.isEmpty else { return }
        let ordered = changes.sorted { $0.range.location < $1.range.location }
        var token: Int?
        var group: Int?
        if case .agent(let turn, let flags, let by) = source {
            group = turn
            let copy = NSMutableString(string: buffer)
            var next = review
            var shift = 0
            for c in ordered {
                let r = NSRange(location: c.range.location + shift, length: c.range.length)
                let before = NSString(string: copy)
                copy.replaceCharacters(in: r, with: c.text)
                next.agent(r, before: before, after: NSString(string: copy), turn: turn, flags: flags, by: by)
                shift += c.text.utf16.count - c.range.length
            }
            token = remember("Changes", before: review, after: next)
        }
        isPlaying = true
        call("quill.play(\(edits(ordered)), \(version), \(token.map(String.init) ?? "null"), \(group.map(String.init) ?? "null"))")
    }

    func land() {
        guard isPlaying else { return }
        call("quill.land()")
    }

    func settled() async {
        guard isPlaying, ready else { return }
        _ = try? await evaluateJavaScript("quill.land()")
        for _ in 0..<30 where isPlaying {
            try? await Task.sleep(for: .milliseconds(16))
        }
    }

    func keep(_ hunks: [Hunk]) {
        var next = review
        let gone = hunks.compactMap { next.remove($0.id) }
        guard !gone.isEmpty else { return }
        let token = remember(gone.count == 1 ? "Keep Change" : "Keep Changes", before: review, after: next)
        setReview(next)
        onResolve?(gone.filter { !$0.touched }, .kept)
        onResolve?(gone.filter(\.touched), .rewritten)
        call("quill.mark(\(token))")
    }

    func revert(_ hunks: [Hunk]) {
        var next = review
        let gone = hunks.compactMap { next.remove($0.id) }
        guard !gone.isEmpty else { return }
        let token = remember(gone.count == 1 ? "Revert Change" : "Revert Changes", before: review, after: next)
        setReview(next)
        onResolve?(gone, .reverted)
        let changes = gone.map { Change(range: $0.range, text: $0.old) }.sorted { $0.range.location < $1.range.location }
        call("quill.apply(\(edits(changes)), \(version), \(token))")
    }

    @objc func undo(_ sender: Any?) { call("quill.undo()") }
    @objc func redo(_ sender: Any?) { call("quill.redo()") }
    @objc func bold(_ sender: Any?) { call("quill.wrap('**')") }
    @objc func italic(_ sender: Any?) { call("quill.wrap('*')") }
    @objc func strike(_ sender: Any?) { call("quill.wrap('~~')") }
    @objc func code(_ sender: Any?) { call("quill.wrap('`')") }
    @objc func heading(_ sender: NSMenuItem) { call("quill.heading(\(sender.tag))") }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(undo(_:)) || item.action == #selector(redo(_:)) { return editable }
        return super.validateUserInterfaceItem(item)
    }

    private func remember(_ name: String, before: Review, after: Review) -> Int {
        tokens += 1
        steps[tokens] = (name, before, after)
        return tokens
    }

    private func pushHunks() {
        let list = review.hunks.map { h -> [String: Any] in
            ["id": h.id, "from": h.range.location, "to": NSMaxRange(h.range), "flagged": !h.flags.isEmpty]
        }
        once("hunks", list.isEmpty ? "quill.hunks([], \(focused.map(String.init) ?? "null"), 0)" : "quill.hunks(\(json(list)), \(focused.map(String.init) ?? "null"), \(version))")
    }

    private func edits(_ changes: [Change]) -> String {
        json(changes.map { [$0.range.location, NSMaxRange($0.range), $0.text] as [Any] })
    }

    func call(_ script: String) {
        guard ready else { return queued.append(script) }
        evaluateJavaScript(script, completionHandler: nil)
    }

    private func json(_ value: Any) -> String {
        if let s = value as? String { return String(data: try! JSONEncoder().encode(s), encoding: .utf8)! }
        return String(data: try! JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]), encoding: .utf8)!
    }

    fileprivate func receive(_ body: [String: Any]) {
        let type = body["type"] as? String
        if let gen = body["generation"] as? Int, gen != generation { return }
        switch type {
        case "ready":
            ready = true
            let scripts = queued
            queued = []
            for script in scripts { evaluateJavaScript(script, completionHandler: nil) }
        case "change":
            changed(body)
        case "select":
            caret(body)
        case "scroll":
            top = body["top"] as? Int ?? 0
            shift = body["shift"] as? CGFloat ?? 0
        case "error":
            NSLog("Quill page: %@", body["message"] as? String ?? "")
        case "played":
            isPlaying = false
            onPlayed?(body["count"] as? Int ?? 0)
        case "hover":
            onHover?(body["id"] as? Int)
        case "keep":
            if let id = body["id"] as? Int { onKeep?(id) }
        case "revert":
            if let id = body["id"] as? Int { onRevert?(id) }
        case "cardHover":
            onCardHover?(body["on"] as? Bool ?? false)
        case "applyNote":
            if let id = body["id"] as? Int { onApplyNote?(id) }
        case "dismissNote":
            if let id = body["id"] as? Int { onDismissNote?(id) }
        case "noteHover":
            onNoteHover?(body["id"] as? Int)
        case "note":
            if let title = body["title"] as? String { onOpenNote?(title) }
        case "embed":
            if let target = body["target"] as? String { onEmbed?(target) }
        case "link":
            if let raw = body["url"] as? String {
                if let url = URL(string: raw), let scheme = url.scheme?.lowercased() {
                    if ["http", "https", "mailto"].contains(scheme) { NSWorkspace.shared.open(url) }
                    else if url.isFileURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                } else { onOpenNote?(raw) }
            }
        default:
            break
        }
    }

    private func changed(_ body: [String: Any]) {
        let changes = (body["changes"] as? [[Any]] ?? []).compactMap { c -> (NSRange, String)? in
            guard let from = c[0] as? Int, let to = c[1] as? Int, let insert = c[2] as? String else { return nil }
            return (NSRange(location: from, length: to - from), insert)
        }
        for (r, insert) in changes.reversed() { buffer.replaceCharacters(in: r, with: insert) }
        version = body["version"] as? Int ?? version
        let marked = (body["steps"] as? [[String: Int]] ?? []).compactMap { s -> (Int, Int)? in
            guard let token = s["token"], let dir = s["dir"] else { return nil }
            return (token, dir)
        }
        let kind = body["kind"] as? String ?? "do"
        if marked.isEmpty {
            for (r, insert) in changes.reversed() { cross(r, length: insert.utf16.count) }
        } else {
            for (token, dir) in marked {
                guard let s = steps[token] else { continue }
                review = dir == 1 ? s.after : s.before
                if kind != "do" { onUndo?(s.name, kind == "undo") }
                if kind == "undo", s.name == "Changes" {
                    onResolve?(s.after.hunks.filter { h in !s.before.hunks.contains { $0.id == h.id } }, .undone)
                }
            }
        }
        caret(body, notify: false)
        if !crossed.isEmpty {
            let gone = crossed
            crossed = []
            let length = buffer.length
            onResolve?(gone.map { h in
                var h = h
                let lo = min(h.range.location, length)
                h.range = NSRange(location: lo, length: min(NSMaxRange(h.range), length) - lo)
                return h
            }, .rewritten)
        }
        pushHunks()
        onReview?()
        if !changes.isEmpty { onEdit?() }
        onCaret?()
    }

    private func cross(_ r: NSRange, length n: Int) {
        let delta = n - r.length
        crossed += review.user(r, length: n).map { h in
            var h = h
            let lo = min(h.range.location, r.location)
            h.range = NSRange(location: lo, length: max(NSMaxRange(h.range), NSMaxRange(r)) + delta - lo)
            return h
        }
    }

    private func caret(_ body: [String: Any], notify: Bool = true) {
        guard let anchor = body["anchor"] as? Int, let head = body["head"] as? Int else { return }
        selection = NSRange(location: min(anchor, head), length: abs(head - anchor))
        if notify { onCaret?() }
    }
}

private final class Relay: NSObject, WKScriptMessageHandler {
    weak var page: Page?

    init(_ page: Page) { self.page = page }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        MainActor.assumeIsolated { page?.receive(body) }
    }
}

extension Page: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        let stays = action.targetFrame?.isMainFrame == false || action.request.url?.standardizedFileURL.path == Brand.url("Editor")?.appending(path: "index.html").standardizedFileURL.path
        decisionHandler(stays ? .allow : .cancel)
    }
}
