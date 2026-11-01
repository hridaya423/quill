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

@MainActor
@Observable
final class Workspace {
    var vault: URL
    var notes: [Note] = []
    var current: URL?
    var phase: Phase = .idle {
        didSet { remedy = nil }
    }
    var level: Float = 0
    var margin: [MarginNote] = []
    var installed: [String: Bool] = [:]
    var remedy: (label: String, action: () -> Void)?
    @ObservationIgnored var showSettings: () -> Void = {}
    var hasKey = Keychain.anthropicKey?.isEmpty == false
    var mode: Mode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "mode") }
    }
    var agentID: String {
        didSet {
            guard agentID != oldValue else { return }
            UserDefaults.standard.set(agentID, forKey: "agent")
            swapAgent()
        }
    }

    @ObservationIgnored weak var editor: QuillTextView?
    @ObservationIgnored var choreographer: Choreographer?
    @ObservationIgnored private var base = ""
    @ObservationIgnored private var inTurn = false
    @ObservationIgnored private var turn = 0
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var settle: Task<Void, Never>?
    @ObservationIgnored private var stream: FSEventStreamRef?
    @ObservationIgnored private var agent: Agent
    @ObservationIgnored private var reply = ""
    @ObservationIgnored private var places: [URL: (NSRange, CGFloat)] = [:]
    @ObservationIgnored private var held: [Tell] = []
    @ObservationIgnored private var proposedDoc: String?
    @ObservationIgnored private var briefed: String?
    @ObservationIgnored private var undone: Set<Int> = []
    @ObservationIgnored private var captures: [Int: () -> Void] = [:]
    @ObservationIgnored lazy var keeper = VoiceKeeper(vault: vault, spec: spec)
    @ObservationIgnored let listener = Listener()
    @ObservationIgnored var turnStarted: CFAbsoluteTime = 0
    @ObservationIgnored var firstChangeAt: CFAbsoluteTime?

    init(vault: URL) {
        self.vault = vault
        mode = Mode(rawValue: UserDefaults.standard.string(forKey: "mode") ?? "") ?? .guided
        let id = UserDefaults.standard.string(forKey: "agent") ?? "claude"
        agentID = id
        agent = AgentSpec.named(id).make()
        listener.onPartial = { [weak self] text in
            if case .listening = self?.phase { self?.phase = .listening(text) }
        }
        listener.onLevel = { [weak self] value in self?.level = value }
    }

    var spec: AgentSpec { AgentSpec.named(agentID) }

    func available(_ spec: AgentSpec) -> Bool? {
        guard let binary = spec.requires else { return hasKey }
        return installed[binary]
    }

    func checkAgents() {
        Task {
            for binary in Set(AgentSpec.all.compactMap(\.requires)) {
                installed[binary] = await Quill.installed(binary)
            }
        }
    }

    private func swapAgent() {
        endTurn()
        keeper.spec = spec
        briefed = nil
        agent.shutdown()
        agent = spec.make()
        warm()
    }

    func warm() {
        let agent = agent, vault = vault
        Task { try? await agent.prepare(cwd: vault) }
        Task { try? await listener.prepare() }
    }

    func start() {
        try? FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        refresh()
        watch()
        warm()
        checkAgents()
        keeper = VoiceKeeper(vault: vault, spec: spec)
        let measured = UserDefaults.standard.double(forKey: "measuredAt")
        if !FileManager.default.fileExists(atPath: keeper.url.path) || Date.now.timeIntervalSince1970 - measured > 86_400 {
            Task { await measure() }
        }
        let last = UserDefaults.standard.string(forKey: "last").map { URL(fileURLWithPath: $0) }
        if current == nil, let url = notes.first(where: { $0.url.path == last?.path })?.url ?? notes.first?.url { open(url) }
    }

    func switchVault(_ url: URL) {
        endTurn()
        flushSave()
        leave()
        if let stream { FSEventStreamStop(stream); FSEventStreamInvalidate(stream); FSEventStreamRelease(stream) }
        stream = nil
        vault = url
        UserDefaults.standard.set(url.path, forKey: "vault")
        current = nil
        editor?.text = ""
        agent.shutdown()
        agent = spec.make()
        start()
    }

    func refresh() {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        let found = FileManager.default.enumerator(at: vault, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants])?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension.lowercased() == "md" }
            .map { url in Note(url: url, modified: (try? url.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast) }
            ?? []
        notes = found.sorted { $0.modified > $1.modified }
    }

    func open(_ url: URL) {
        guard url != current else { return }
        endTurn()
        choreographer?.land()
        flushSave()
        leave()
        margin = []
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        current = url
        UserDefaults.standard.set(url.path, forKey: "last")
        base = text
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
                UserDefaults.standard.set(target.path, forKey: "last")
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
        guard !inTurn else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    func flushSave() {
        guard saveTask != nil else { return }
        saveTask?.cancel()
        saveTask = nil
        save()
    }

    private func save() {
        saveTask = nil
        guard let url = current, let editor, !inTurn else { return }
        let text = editor.string
        guard text != base else { return }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            base = text
        } catch {
            phase = .failed("Couldn't save \(url.lastPathComponent).")
        }
    }

    func reconcile() {
        guard let url = current, let editor, let choreographer else { return }
        guard let disk = try? String(contentsOf: url, encoding: .utf8), disk != base else { return }
        if choreographer.isBusy {
            guard settle == nil else { return }
            settle = Task { [weak self] in
                while self?.choreographer?.isBusy == true, !Task.isCancelled { try? await Task.sleep(for: .milliseconds(60)) }
                guard !Task.isCancelled else { return }
                self?.settle = nil
                self?.reconcile()
            }
            return
        }
        propose(disk, editor: editor)
    }

    var voiceSources: [URL] {
        [vault] + (UserDefaults.standard.stringArray(forKey: "voiceSources") ?? []).map { URL(fileURLWithPath: $0) }.filter { $0 != vault }
    }

    @discardableResult
    func measure() async -> Fingerprint {
        let f = await keeper.measure(voiceSources)
        UserDefaults.standard.set(f.punctuation["em dashes"] ?? 0, forKey: "emDash")
        refresh()
        return f
    }

    private func propose(_ text: String, editor: QuillTextView) {
        if inTurn, let url = current {
            let (old, new) = changedParagraphs(base: base, proposed: text)
            let bad = introducedTells(before: old, after: new, allowEmDash: UserDefaults.standard.double(forKey: "emDash") >= 2)
            if !bad.isEmpty {
                held += bad
                try? editor.string.write(to: url, atomically: true, encoding: .utf8)
                base = editor.string
                Ledger.event("held", detail: bad.map { "\($0.kind): \($0.phrase)" }.joined(separator: "; "))
                return
            }
            proposedDoc = text
        }
        let changes = merge(base: base, current: editor.string, proposed: text)
        base = text
        guard !changes.isEmpty else { return }
        if firstChangeAt == nil { firstChangeAt = CFAbsoluteTimeGetCurrent() }
        if inTurn { phase = .applying(changes.count) }
        choreographer?.play(changes)
    }

    func finishedPlaying(_ count: Int) {
        if !inTurn {
            if case .applying = phase { phase = .done(count) }
            flushOrSave()
        }
    }

    private func flushOrSave() {
        saveTask?.cancel()
        save()
    }

    func ask(_ words: String) {
        let words = words.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty, let url = current, let editor, !inTurn else {
            if words.isEmpty { phase = .idle }
            return
        }
        if available(spec) == false {
            let spec = spec
            Task { [weak self] in
                guard let self else { return }
                if let binary = spec.requires { installed[binary] = await Quill.installed(binary) }
                if available(spec) == false {
                    let need = spec.requires == nil ? "an API key" : spec.requires == "npx" ? "Node" : "the \(spec.requires!) command"
                    fail("\(spec.name) needs \(need). Install it, or choose another co-writer.", remedy: ("Choose…", { [weak self] in self?.showSettings() }))
                } else {
                    ask(words)
                }
            }
            return
        }
        choreographer?.land()
        flushOrSave()
        let text = editor.string
        base = text
        let sel = editor.selectedRange()
        let selection = sel.length > 0 ? (text as NSString).substring(with: sel) : nil
        let request = Request(words: words, path: url.path, text: text, selection: selection, mode: mode)
        inTurn = true
        turn += 1
        let id = turn
        editor.undoTag = id
        held = []
        proposedDoc = nil
        var retried = false
        let before = text
        let voice = keeper.notes
        reply = ""
        margin = []
        turnStarted = CFAbsoluteTimeGetCurrent()
        firstChangeAt = nil
        phase = .thinking("Reading", words: words)
        let agent = agent
        Task {
            var failure: String?
            do {
                try await agent.prepare(cwd: vault)
                guard turn == id else { return }
                let brief = agent.conversation == nil || agent.conversation != briefed
                var body = prompt(request, canEditFiles: agent.canEditFiles, voice: voice, briefing: brief ? Floor.text : nil)
                for attempt in 0..<2 {
                    try await agent.send(body, base: self.editor?.string ?? text) { [weak self] event in
                        guard let self, self.turn == id else { return }
                        switch event {
                        case .activity(let a):
                            if case .thinking = self.phase { self.phase = .thinking(a, words: words) }
                        case .text(let t):
                            self.reply += t
                        case .proposed(let next):
                            do {
                                try next.write(to: url, atomically: true, encoding: .utf8)
                                self.reconcile()
                            } catch {
                                self.phase = .failed("Couldn't save \(url.lastPathComponent).")
                            }
                        }
                    }
                    guard turn == id else { return }
                    briefed = agent.conversation
                    try? await Task.sleep(for: .milliseconds(150))
                    reconcile()
                    guard !held.isEmpty, attempt == 0 else { break }
                    retried = true
                    phase = .thinking("Revising", words: words)
                    reply = ""
                    body = retryPrompt(held, canEditFiles: agent.canEditFiles)
                    held = []
                }
            } catch {
                failure = error.localizedDescription
            }
            guard turn == id else { return }
            await settleTurn(failure: failure, words: words)
            record(id: id, note: url, request: words, before: before, retried: retried)
        }
    }

    private func settleTurn(failure: String?, words: String) async {
        reconcile()
        while choreographer?.isBusy == true || settle != nil {
            try? await Task.sleep(for: .milliseconds(50))
        }
        inTurn = false
        flushOrSave()
        let latency = firstChangeAt.map { $0 - turnStarted }
        Log.turn(words: words, agent: agentID, total: CFAbsoluteTimeGetCurrent() - turnStarted, firstChange: latency)
        if let failure {
            phase = .failed(failure)
            return
        }
        let said = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        if !held.isEmpty, proposedDoc == nil {
            let phrases = Array(Set(held.map { "“\($0.phrase.trimmingCharacters(in: .whitespaces))”" })).prefix(2).joined(separator: " and ")
            phase = .said("I held back an edit that used \(phrases). Ask again and I'll try another way.")
            return
        }
        if mode == .notes, let editor, let found = QuillCore.notes(from: said, in: editor.string), !found.isEmpty {
            margin = found
            phase = .said(found.count == 1 ? "One note in the margin." : "\(found.count) notes in the margin.")
        } else if case .applying(let n) = phase {
            phase = said.isEmpty ? .done(n) : .said(said)
        } else {
            phase = said.isEmpty ? .done(0) : .said(said)
        }
    }

    private func retryPrompt(_ tells: [Tell], canEditFiles: Bool) -> String {
        let list = tells.map { "- \($0.kind): “\($0.phrase)”" }.joined(separator: "\n")
        return """
        Quill did not apply your last edit. It introduced patterns the writer's editorial rules forbid:
        \(list)
        The document is back to how it was before that edit. Make the edit again without these patterns, \(canEditFiles ? "editing the file directly" : "calling the edit tool"). Keep everything else the same. Then reply as before.
        """
    }

    private func record(id: Int, note: URL, request: String, before: String, retried: Bool) {
        guard let proposed = proposedDoc else {
            if !held.isEmpty || retried {
                Ledger.append(TurnRecord(id: UUID().uuidString, at: .now, note: note.lastPathComponent, request: request, mode: mode.rawValue,
                                         agent: agentID, held: held.map(\.phrase), retried: retried, exchanges: []), to: Ledger.turns)
            }
            return
        }
        let held = held.map(\.phrase), mode = mode.rawValue, agent = agentID
        let capture = { [weak self] in
            guard let self else { return }
            self.captures[id] = nil
            let kept = self.current == note ? self.editor?.string ?? "" : (try? String(contentsOf: note, encoding: .utf8)) ?? ""
            var found = exchanges(request: request, before: before, proposed: proposed, kept: kept)
            if self.undone.contains(id) {
                found = found.map { var e = $0; if e.outcome == .reverted { e.outcome = .undone }; return e }
            }
            Ledger.append(TurnRecord(id: UUID().uuidString, at: .now, note: note.lastPathComponent, request: request, mode: mode,
                                     agent: agent, held: held, retried: retried, exchanges: found), to: Ledger.turns)
            self.keeper.distillIfDue()
        }
        captures[id] = capture
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(60))
            self?.captures[id]?()
        }
    }

    func undid(_ tag: Int) {
        if undone.contains(tag) {
            undone.remove(tag)
            Ledger.event("redo", turn: String(tag))
        } else {
            undone.insert(tag)
            Ledger.event("undo", turn: String(tag))
        }
    }

    func fail(_ message: String, remedy: (String, () -> Void)? = nil) {
        phase = .failed(message)
        self.remedy = remedy.map { (label: $0.0, action: $0.1) }
    }

    func cancelTurn() {
        if listener.isListening { listener.cancel() }
        if inTurn { endTurn() } else { phase = .idle }
    }

    func endTurn() {
        guard inTurn else { return }
        agent.cancel()
        turn += 1
        settle?.cancel()
        settle = nil
        choreographer?.land()
        reconcile()
        choreographer?.land()
        inTurn = false
        phase = .idle
        flushOrSave()
    }

    func quit() {
        for capture in Array(captures.values) { capture() }
        endTurn()
        choreographer?.land()
        flushSave()
        leave()
        agent.shutdown()
    }

    private func watch() {
        let paths = [vault.path] as CFArray
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let ws = Unmanaged<Workspace>.fromOpaque(info).takeUnretainedValue()
            MainActor.assumeIsolated {
                ws.reconcile()
                ws.refresh()
            }
        }
        guard let s = FSEventStreamCreate(nil, callback, &context, paths, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.03,
                                          FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer))
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
