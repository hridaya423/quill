import AppKit
import CoreServices
import Observation
import QuillCore

enum Phase: Equatable {
    case idle
    case listening(String)
    case thinking(String, words: String)
    case applying(Int)
    case said(String)
    case done(Int)
    case failed(String)
}

struct Note: Identifiable, Hashable {
    var url: URL
    var modified: Date
    var id: URL { url }
    var title: String { url.deletingPathExtension().lastPathComponent }
}

struct Line: Identifiable, Equatable {
    var id = UUID()
    var words: String
    var reply: String
    var failed = false
}

struct Asked {
    var id = UUID().uuidString
    var note: String
    var request: String
    var mode: Mode
    var agent: String
    var held: [String] = []
    var retried = false
    var exchanges: [Exchange] = []
}

@MainActor
@Observable
final class Workspace {
    static let desk = Ledger.dir.appending(path: "desk")

    var vault: URL
    var notes: [Note] = []
    var current: URL?
    var phase: Phase = .idle {
        didSet { remedy = nil }
    }
    var level: Float = 0
    var margin: [MarginNote] = []
    var review = Review()
    var transcript: [URL: [Line]] = [:]
    var installed: [String: Bool] = [:]
    var remedy: (label: String, action: () -> Void)?
    var busy = false
    var live = ""
    var focusID: Int?
    var model: ModelChoice?
    var models: [ModelChoice] = []
    @ObservationIgnored var showSettings: (Pane?) -> Void = { _ in }
    var keyed = Set(AgentSpec.all.filter { Keychain.key(for: $0.id) != nil }.map(\.id))
    var mode: Mode {
        didSet { Prefs.mode = mode }
    }
    var agentID: String {
        didSet {
            guard agentID != oldValue else { return }
            Prefs.agent = agentID
            swapAgent()
        }
    }

    @ObservationIgnored weak var editor: QuillTextView?
    @ObservationIgnored var choreographer: Choreographer?
    @ObservationIgnored private var saved = ""
    @ObservationIgnored private var deskBase = ""
    @ObservationIgnored private var deskFile: URL?
    @ObservationIgnored private var holding = true
    @ObservationIgnored private var turn = 0
    @ObservationIgnored private var asked: [Int: Asked] = [:]
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var settle: Task<Void, Never>?
    @ObservationIgnored private var stream: FSEventStreamRef?
    @ObservationIgnored private var agent: Agent
    @ObservationIgnored private var reply = ""
    @ObservationIgnored private var tagged: String?
    @ObservationIgnored private var places: [URL: (NSRange, CGFloat)] = [:]
    @ObservationIgnored private var held: [Tell] = []
    @ObservationIgnored private var proposed = false
    @ObservationIgnored private var briefed: String?
    @ObservationIgnored lazy var keeper = VoiceKeeper(vault: vault, spec: spec)
    @ObservationIgnored let listener = Listener()
    @ObservationIgnored var turnStarted: CFAbsoluteTime = 0
    @ObservationIgnored var firstChangeAt: CFAbsoluteTime?

    init(vault: URL) {
        self.vault = vault
        mode = Prefs.mode
        let id = Prefs.agent
        agentID = id
        agent = AgentSpec.named(id).make()
        listener.onPartial = { [weak self] text in
            if case .listening = self?.phase { self?.phase = .listening(text) }
        }
        listener.onLevel = { [weak self] value in self?.level = value }
    }

    var spec: AgentSpec { AgentSpec.named(agentID) }

    var recommended: [ModelChoice] {
        var picks = spec.picks.compactMap { id in models.first { $0.id == id } }
        if picks.isEmpty { picks = Array(models.prefix(3)) }
        if let model, !picks.contains(model) { picks = Array(picks.prefix(2)) + [model] }
        return picks
    }

    func available(_ spec: AgentSpec) -> Bool? {
        switch spec.kind {
        case .anthropic: return keyed.contains(spec.id)
        case .chat: return spec.keys.isEmpty || keyed.contains(spec.id)
        case .registry(_, _, false): return true
        default:
            let found = spec.binaries.map { installed[$0] }
            if found.contains(true) { return true }
            return found.contains(nil) ? nil : false
        }
    }

    func checkAgents() {
        Task {
            for binary in Set(AgentSpec.all.flatMap(\.binaries)) {
                installed[binary] = await Shell.find(binary) != nil
            }
        }
    }

    func attach(_ editor: QuillTextView, _ choreographer: Choreographer) {
        self.editor = editor
        self.choreographer = choreographer
        editor.onReview = { [weak self, weak editor] in
            guard let self, let editor, self.review != editor.review else { return }
            self.review = editor.review
        }
        editor.onResolve = { [weak self] hunks, outcome in self?.resolved(hunks, outcome) }
        editor.onUndo = { name, back in Ledger.event(back ? "undo" : "redo", detail: name) }
    }

    func replace(_ agent: Agent) {
        self.agent.shutdown()
        self.agent = agent
    }

    private func swapAgent() {
        endTurn()
        keeper.spec = spec
        briefed = nil
        agent.shutdown()
        agent = spec.make()
        models = []
        model = nil
        warm()
    }

    func warm() {
        let agent = agent
        Task {
            try? await agent.prepare(cwd: Self.desk, readable: reachable)
            sync()
        }
        Task { try? await listener.prepare() }
    }

    private func sync() {
        if models != agent.models { models = agent.models }
        if model != agent.model { model = agent.model }
    }

    func choose(model id: String) {
        Prefs.setModel(id, for: agentID)
        let agent = agent
        Task {
            do { try await agent.choose(model: id) } catch { fail(error.localizedDescription) }
            sync()
        }
    }

    func start() {
        try? FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: Self.desk, withIntermediateDirectories: true)
        refresh()
        watch()
        warm()
        checkAgents()
        keeper = VoiceKeeper(vault: vault, spec: spec)
        if !FileManager.default.fileExists(atPath: keeper.url.path) || Date.now.timeIntervalSince1970 - Prefs.measuredAt > 86_400 {
            Task { await measure() }
        }
        let last = Prefs.last.map { URL(fileURLWithPath: $0) }
        if current == nil, let url = notes.first(where: { $0.url.path == last?.path })?.url ?? notes.first?.url { open(url) }
    }

    func switchVault(_ url: URL) {
        endTurn()
        leave()
        unwatch()
        vault = url
        Prefs.vault = url.path
        current = nil
        editor?.text = ""
        agent.shutdown()
        agent = spec.make()
        start()
    }

    var title: String {
        FileManager.default.displayName(atPath: vault.path)
    }

    func refresh() {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        let found = FileManager.default.enumerator(at: vault, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants])?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension.lowercased() == "md" }
            .map { url in Note(url: url, modified: (try? url.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast) }
            ?? []
        let sorted = found.sorted { $0.modified > $1.modified }
        if sorted != notes { notes = sorted }
    }

    func open(_ url: URL) {
        guard url != current else { return }
        endTurn()
        leave()
        margin = []
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        current = url
        if url.path.hasPrefix(vault.path) { Prefs.last = url.path }
        saved = text
        editor?.text = text
        let (selection, y) = places[url] ?? (NSRange(location: 0, length: 0), 0)
        editor?.setSelectedRange(NSMaxRange(selection) <= (text as NSString).length ? selection : NSRange(location: 0, length: 0))
        if y > 0, let editor, let tlm = editor.textLayoutManager {
            tlm.ensureLayout(for: CGRect(x: 0, y: 0, width: editor.bounds.width, height: y + 2000))
        }
        editor?.layoutSubtreeIfNeeded()
        editor?.scroll(NSPoint(x: 0, y: y))
        if case .failed = phase { phase = .idle }
    }

    private func leave() {
        choreographer?.land()
        settleReview()
        flushSave()
        guard let url = current, let editor else { return }
        places[url] = (editor.selectedRange(), editor.enclosingScrollView?.contentView.bounds.origin.y ?? 0)
        let name = url.deletingPathExtension().lastPathComponent
        guard name.wholeMatch(of: /Untitled( \d+)?/) != nil,
              let first = editor.string.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first,
              first.hasPrefix("# ")
        else { return }
        let heading = first.dropFirst(2)
            .replacingOccurrences(of: ":", with: "-")
            .filter { !"*_`#[]".contains($0) }
            .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ".")))
        guard !heading.isEmpty else { return }
        rename(Note(url: url, modified: .now), to: String(heading.prefix(80)))
        if let renamed = current, renamed != url { places[renamed] = places.removeValue(forKey: url) }
    }

    private func settleReview() {
        guard let editor, !editor.review.isEmpty else { return }
        let hunks = editor.review.hunks
        editor.setReview(Review())
        editor.undoManager?.removeAllActions()
        resolved(hunks, .unreviewed)
    }

    func create() {
        var name = "Untitled"
        var n = 2
        while FileManager.default.fileExists(atPath: vault.appending(path: "\(name).md").path) {
            name = "Untitled \(n)"
            n += 1
        }
        let url = vault.appending(path: "\(name).md")
        try? "# \n".write(to: url, atomically: true, encoding: .utf8)
        refresh()
        open(url)
        editor?.setSelectedRange(NSRange(location: 2, length: 0))
        editor?.window?.makeFirstResponder(editor)
    }

    @discardableResult
    func rename(_ note: Note, to title: String) -> String? {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "/", with: "-")
        guard !clean.isEmpty, clean != note.title else { return nil }
        if note.url == current { endTurn() }
        let target = note.url.deletingLastPathComponent().appending(path: "\(clean).md")
        guard !FileManager.default.fileExists(atPath: target.path) else { return "There's already a note named “\(clean)”." }
        flushSave()
        do {
            try FileManager.default.moveItem(at: note.url, to: target)
            if current == note.url {
                current = target
                Prefs.last = target.path
                transcript[target] = transcript.removeValue(forKey: note.url)
            }
            refresh()
            return nil
        } catch {
            return "Couldn't rename “\(note.title)”."
        }
    }

    func trash(_ note: Note) {
        if current == note.url {
            endTurn()
            choreographer?.land()
            editor?.setReview(Review())
            current = nil
            editor?.text = ""
        }
        try? FileManager.default.trashItem(at: note.url, resultingItemURL: nil)
        refresh()
        if current == nil, let first = notes.first { open(first.url) }
    }

    func edited() {
        if !margin.isEmpty, let editor {
            let doc = editor.string as NSString
            let moved = margin.compactMap { note -> MarginNote? in
                var note = note
                note.range = doc.range(of: note.quote, options: [.caseInsensitive, .diacriticInsensitive])
                return note.range.location == NSNotFound ? nil : note
            }
            if moved != margin { margin = moved }
        }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    func flushSave() {
        saveTask?.cancel()
        save()
    }

    private func save() {
        saveTask = nil
        guard let url = current, let editor else { return }
        let text = editor.review.accepted(editor.string)
        guard text != saved else { return }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            saved = text
        } catch {
            fail("Couldn't save \(url.lastPathComponent).")
        }
    }

    private func whenIdle(_ then: @escaping () -> Void) -> Bool {
        guard choreographer?.isBusy == true else { return false }
        guard settle == nil else { return true }
        settle = Task { [weak self] in
            while self?.choreographer?.isBusy == true, !Task.isCancelled { try? await Task.sleep(for: .milliseconds(60)) }
            guard !Task.isCancelled else { return }
            self?.settle = nil
            then()
        }
        return true
    }

    func reconcileVault() {
        guard let url = current, let editor else { return }
        guard let disk = try? String(contentsOf: url, encoding: .utf8), disk != saved else { return }
        if whenIdle({ [weak self] in self?.reconcileVault() }) { return }
        let changes = merge(base: saved, current: editor.string, proposed: disk)
        saved = disk
        choreographer?.play(changes, as: .other, turn: 0)
    }

    func reconcileDesk() {
        guard busy, let file = deskFile, let editor else { return }
        guard let disk = try? String(contentsOf: file, encoding: .utf8), disk != deskBase else { return }
        if whenIdle({ [weak self] in self?.reconcileDesk() }) { return }
        let (old, new) = changedParagraphs(base: deskBase, proposed: disk)
        let bad = introducedTells(before: old, after: new, allowing: Prefs.ownTells)
        if !bad.isEmpty, holding {
            held += bad
            try? deskBase.write(to: file, atomically: true, encoding: .utf8)
            Ledger.event("held", detail: bad.map { "\($0.kind): \($0.phrase)" }.joined(separator: "; "))
            return
        }
        let flags = bad.map { "\($0.kind): “\($0.phrase.trimmingCharacters(in: .whitespaces))”" }
        let changes = merge(base: deskBase, current: editor.string, proposed: disk)
        deskBase = disk
        proposed = true
        guard !changes.isEmpty else { return }
        if firstChangeAt == nil { firstChangeAt = CFAbsoluteTimeGetCurrent() }
        phase = .applying(editor.review.turn(turn).count + changes.count)
        if let first = changes.first { editor.present(editor.paragraph(at: first.range.location)) }
        choreographer?.play(changes, as: .agent(turn: turn, flags: flags), turn: turn)
    }

    var reachable: [URL] { voiceSources + (Guide.skill.map { [$0] } ?? []) }

    var voiceSources: [URL] {
        [vault] + Prefs.voiceSources.map { URL(fileURLWithPath: $0) }.filter { $0 != vault }
    }

    @discardableResult
    func measure() async -> Fingerprint {
        let f = await keeper.measure(voiceSources)
        refresh()
        return f
    }

    func finishedPlaying(_ count: Int) {
        if !busy, case .applying = phase { phase = .done(review.hunks.count) }
    }

    func ask(_ words: String, mode override: Mode? = nil) {
        let words = words.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty, let url = current, let editor, !busy else {
            if words.isEmpty { phase = .idle }
            return
        }
        if available(spec) == false {
            let spec = spec
            Task { [weak self] in
                guard let self else { return }
                for binary in spec.binaries { installed[binary] = await Shell.find(binary) != nil }
                if available(spec) == false {
                    fail("\(spec.name) needs \(spec.need). Install it, or choose another co-writer.", remedy: ("Choose…", { [weak self] in self?.showSettings(.cowriters) }))
                } else {
                    ask(words, mode: override)
                }
            }
            return
        }
        choreographer?.land()
        flushSave()
        let mode = override ?? self.mode
        let text = editor.string
        let title = url.deletingPathExtension().lastPathComponent
        let fm = FileManager.default
        for stale in (try? fm.contentsOfDirectory(at: Self.desk, includingPropertiesForKeys: nil)) ?? [] { try? fm.removeItem(at: stale) }
        try? fm.createDirectory(at: Self.desk, withIntermediateDirectories: true)
        let file = Self.desk.appending(path: "\(title).md")
        do { try text.write(to: file, atomically: true, encoding: .utf8) } catch {
            fail("Couldn't prepare a working copy of \(title).")
            return
        }
        deskFile = file
        deskBase = text
        let sel = editor.selectedRange()
        let selection = sel.length > 0 ? (text as NSString).substring(with: sel) : nil
        let request = Request(words: words, title: title, path: file.path, text: text, selection: selection, mode: mode)
        busy = true
        turn += 1
        let id = turn
        asked[id] = Asked(note: url.lastPathComponent, request: words, mode: mode, agent: agentID)
        held = []
        holding = true
        proposed = false
        tagged = nil
        let voice = keeper.notes
        reply = ""
        live = ""
        margin = []
        if sel.length > 0 { editor.present(editor.paragraph(at: sel.location)) } else { editor.sweep() }
        turnStarted = CFAbsoluteTimeGetCurrent()
        firstChangeAt = nil
        phase = .thinking(sel.length > 0 ? "Reading the selection" : "Reading the note", words: words)
        let agent = agent
        Task {
            var failure: String?
            do {
                Registry.status = { [weak self] note in
                    guard let self, case .thinking(_, let w) = phase else { return }
                    phase = .thinking(note, words: w)
                }
                try await agent.prepare(cwd: Self.desk, readable: reachable)
                sync()
                guard turn == id else { return }
                let brief = agent.conversation == nil || agent.conversation != briefed
                var body = prompt(request, canEditFiles: agent.canEditFiles, voice: voice, briefing: brief ? Guide.briefing() : nil)
                for attempt in 0..<2 {
                    try await agent.send(body, file: file, base: deskBase) { event in
                        guard self.turn == id else { return }
                        switch event {
                        case .activity(let a):
                            if case .thinking(_, let w) = self.phase { self.phase = .thinking(a, words: w) }
                        case .text(let t):
                            self.reply += t
                            self.live = readable(self.reply)
                        case .focus(let passage):
                            self.focus(passage)
                        case .proposed(let next):
                            try? next.write(to: file, atomically: true, encoding: .utf8)
                            self.reconcileDesk()
                        case .notes(let json):
                            self.tagged = json
                        }
                    }
                    guard turn == id else { return }
                    briefed = agent.conversation
                    try? await Task.sleep(for: .milliseconds(150))
                    reconcileDesk()
                    guard !held.isEmpty, attempt == 0 else { break }
                    asked[id]?.held = held.map(\.phrase)
                    asked[id]?.retried = true
                    holding = false
                    let phrases = Array(Set(held.map { "“\($0.phrase.trimmingCharacters(in: .whitespaces))”" })).prefix(2).joined(separator: " and ")
                    phase = .thinking("Rewriting without \(phrases)", words: words)
                    reply = ""
                    body = retryPrompt(held, canEditFiles: agent.canEditFiles)
                    held = []
                }
            } catch {
                failure = error.localizedDescription
            }
            guard turn == id else { return }
            await settleTurn(id: id, url: url, failure: failure, words: words, mode: mode)
        }
    }

    private func settleTurn(id: Int, url: URL, failure: String?, words: String, mode: Mode) async {
        reconcileDesk()
        while choreographer?.isBusy == true || settle != nil {
            try? await Task.sleep(for: .milliseconds(50))
        }
        busy = false
        deskFile = nil
        editor?.present(nil)
        flushSave()
        let latency = firstChangeAt.map { $0 - turnStarted }
        Log.turn(words: words, agent: agentID, total: CFAbsoluteTimeGetCurrent() - turnStarted, firstChange: latency)
        defer { close(id) }
        if let failure {
            transcript[url, default: []].append(Line(words: words, reply: failure, failed: true))
            phase = .failed(failure)
            return
        }
        let raw = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        let said = readable(raw)
        let pending = editor?.review.turn(id).count ?? 0
        if mode == .notes || raw.contains("<notes>") || tagged != nil, let editor,
           let found = QuillCore.notes(from: tagged.map { "<notes>\($0)</notes>" } ?? raw, in: editor.string), !found.isEmpty {
            margin = found
            let summary = found.count == 1 ? "One note in the margin." : "\(found.count) notes in the margin."
            transcript[url, default: []].append(Line(words: words, reply: summary))
            phase = .said(summary)
            return
        }
        if asked[id]?.retried == true, !proposed {
            let summary = said.isEmpty ? "I couldn't make that edit without breaking your rules. Try asking another way." : said
            transcript[url, default: []].append(Line(words: words, reply: summary))
            phase = .said(summary)
            return
        }
        let summary = said.isEmpty ? (pending == 0 ? "Nothing to change." : pending == 1 ? "1 change." : "\(pending) changes.") : said
        transcript[url, default: []].append(Line(words: words, reply: summary))
        phase = said.isEmpty ? .done(pending) : .said(said)
    }

    private func focus(_ passage: String) {
        guard let editor else { return }
        let doc = editor.string as NSString
        var r = doc.range(of: passage)
        if r.location == NSNotFound, let line = passage.split(separator: "\n").first(where: { $0.count > 12 }) { r = doc.range(of: String(line)) }
        guard r.location != NSNotFound else { return }
        editor.present(editor.paragraph(at: r.location))
        if case .thinking(_, let w) = phase { phase = .thinking("Editing here", words: w) }
    }

    private func retryPrompt(_ tells: [Tell], canEditFiles: Bool) -> String {
        let list = tells.map { "- \($0.kind): “\($0.phrase)”" }.joined(separator: "\n")
        return """
        Quill did not apply your last edit. It introduced patterns the writer's editorial rules forbid:
        \(list)
        The working copy is back to how it was before that edit. Make the edit again without these patterns, \(canEditFiles ? "editing the file directly" : "calling the edit tool"). Keep everything else the same. Then reply as before.
        """
    }

    private func resolved(_ hunks: [Hunk], _ outcome: Outcome) {
        guard let editor, !hunks.isEmpty else { return }
        let doc = NSString(string: editor.string)
        for h in hunks {
            guard asked[h.turn] != nil, NSMaxRange(h.range) <= doc.length else { continue }
            var e = exchange(h, request: asked[h.turn]?.request ?? "", outcome: outcome, in: doc, at: h.range)
            if outcome == .reverted || outcome == .undone { e.final = e.before }
            asked[h.turn]?.exchanges.append(e)
        }
        Ledger.event(outcome.rawValue, detail: "\(hunks.count)")
        for t in Set(hunks.map(\.turn)) where !(busy && t == turn) {
            let left = editor.review.turn(t).filter { h in !hunks.contains { $0.id == h.id } }
            if left.isEmpty { close(t, force: true) }
        }
    }

    private func close(_ id: Int, force: Bool = false) {
        guard let a = asked[id], force || editor?.review.turn(id).isEmpty ?? true else { return }
        asked[id] = nil
        guard !a.exchanges.isEmpty || !a.held.isEmpty || a.retried else { return }
        Ledger.append(TurnRecord(id: a.id, at: .now, note: a.note, request: a.request, mode: a.mode.rawValue,
                                 agent: a.agent, held: a.held, retried: a.retried, exchanges: a.exchanges), to: Ledger.turns)
        if !a.exchanges.isEmpty { keeper.distillIfDue() }
    }

    func keep(_ hunks: [Hunk]? = nil) {
        guard let editor else { return }
        choreographer?.land()
        editor.keep(hunks ?? editor.review.hunks)
        if editor.review.isEmpty, case .done = phase { phase = .idle }
    }

    func revert(_ hunks: [Hunk]? = nil) {
        guard let editor else { return }
        choreographer?.land()
        editor.revert(hunks ?? editor.review.hunks)
        if editor.review.isEmpty, case .done = phase { phase = .idle }
    }

    var focused: Hunk? {
        guard let editor else { return nil }
        let sel = editor.selectedRange()
        return editor.review.hunks.first { NSIntersectionRange($0.range, sel).length > 0 || NSLocationInRange(sel.location, $0.range) || sel.location == NSMaxRange($0.range) }
    }

    func step(_ forward: Bool) {
        guard let editor, !editor.review.isEmpty else { return }
        let at = editor.selectedRange().location
        let hunks = editor.review.hunks
        let next = forward
            ? hunks.first { $0.range.location > at } ?? hunks.first
            : hunks.last { NSMaxRange($0.range) < at } ?? hunks.last
        guard let next else { return }
        editor.setSelectedRange(NSRange(location: next.range.location, length: 0))
        editor.scrollRangeToVisible(next.range)
    }

    func fail(_ message: String, remedy: (String, () -> Void)? = nil) {
        phase = .failed(message)
        self.remedy = remedy.map { (label: $0.0, action: $0.1) }
    }

    func cancelTurn() {
        if listener.isListening { listener.cancel() }
        if busy { endTurn() } else { phase = .idle }
    }

    func endTurn() {
        guard busy else { return }
        agent.cancel()
        let id = turn
        turn += 1
        settle?.cancel()
        settle = nil
        choreographer?.land()
        busy = false
        deskFile = nil
        editor?.present(nil)
        phase = .idle
        close(id)
        flushSave()
    }

    func quit() {
        endTurn()
        leave()
        unwatch()
        agent.shutdown()
    }

    private func unwatch() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private func watch() {
        let paths = [vault.path, Self.desk.path] as CFArray
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, paths, _, _ in
            guard let info else { return }
            let ws = Unmanaged<Workspace>.fromOpaque(info).takeUnretainedValue()
            let changed = (unsafeBitCast(paths, to: NSArray.self) as? [String]) ?? []
            MainActor.assumeIsolated {
                let desk = Workspace.desk.resolvingSymlinksInPath().path
                if changed.contains(where: { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path.hasPrefix(desk) }) { ws.reconcileDesk() }
                if changed.contains(where: { !URL(fileURLWithPath: $0).resolvingSymlinksInPath().path.hasPrefix(desk) }) {
                    ws.reconcileVault()
                    ws.refresh()
                }
            }
        }
        let flags = kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagUseCFTypes
        guard let s = FSEventStreamCreate(nil, callback, &context, paths, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.03, FSEventStreamCreateFlags(flags))
        else { return }
        FSEventStreamSetDispatchQueue(s, .main)
        FSEventStreamStart(s)
        stream = s
    }
}

enum Log {
    static func turn(words: String, agent: String, total: Double, firstChange: Double?) {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appending(path: "Logs/Quill")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appending(path: "turns.tsv")
        let line = "\(ISO8601DateFormatter().string(from: Date()))\t\(agent)\t\(String(format: "%.2f", total))\t\(firstChange.map { String(format: "%.2f", $0) } ?? "-")\t\(words.replacingOccurrences(of: "\t", with: " "))\n"
        if let h = try? FileHandle(forWritingTo: file) {
            _ = try? h.seekToEnd()
            h.write(Data(line.utf8))
            try? h.close()
        } else {
            try? line.write(to: file, atomically: true, encoding: .utf8)
        }
    }
}
