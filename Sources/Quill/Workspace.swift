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
    var phase: Phase = .idle
    var level: Float = 0
    var margin: [MarginNote] = []
    var mode: Mode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "mode") }
    }
    var agentID: String {
        didSet {
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

    private func swapAgent() {
        endTurn()
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
        if current == nil, let first = notes.first { open(first.url) }
    }

    func switchVault(_ url: URL) {
        endTurn()
        flushSave()
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
        margin = []
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        current = url
        base = text
        editor?.text = text
        editor?.setSelectedRange(NSRange(location: 0, length: 0))
        editor?.scroll(.zero)
        if case .failed = phase { phase = .idle }
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

    func rename(_ note: Note, to title: String) {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "/", with: "-")
        guard !clean.isEmpty, clean != note.title else { return }
        let target = note.url.deletingLastPathComponent().appending(path: "\(clean).md")
        guard !FileManager.default.fileExists(atPath: target.path) else { return }
        flushSave()
        do {
            try FileManager.default.moveItem(at: note.url, to: target)
            if current == note.url { current = target }
            refresh()
        } catch {}
    }

    func trash(_ note: Note) {
        if current == note.url {
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

    private func propose(_ text: String, editor: QuillTextView) {
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
        choreographer?.land()
        flushOrSave()
        let text = editor.string
        base = text
        let sel = editor.selectedRange()
        let selection = sel.length > 0 ? (text as NSString).substring(with: sel) : nil
        let request = Request(words: words, path: url.path, text: text, selection: selection, mode: mode)
        let body = prompt(request, canEditFiles: agent.canEditFiles)
        inTurn = true
        turn += 1
        let id = turn
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
                try await agent.send(body, base: text) { [weak self] event in
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
            } catch {
                failure = error.localizedDescription
            }
            guard turn == id else { return }
            await settleTurn(failure: failure, words: words)
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
        if mode == .notes, let editor, let found = QuillCore.notes(from: said, in: editor.string), !found.isEmpty {
            margin = found
            phase = .said(found.count == 1 ? "One note in the margin." : "\(found.count) notes in the margin.")
        } else if case .applying(let n) = phase {
            phase = said.isEmpty ? .done(n) : .said(said)
        } else {
            phase = said.isEmpty ? .done(0) : .said(said)
        }
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
        endTurn()
        choreographer?.land()
        flushSave()
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
