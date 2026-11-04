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

struct Mention: Hashable, Identifiable {
    var url: URL
    var insert: String
    var folder: Bool
    var id: URL { url }
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
    static let desks = Ledger.dir.appending(path: "desk")
    let desk: URL
    nonisolated static let skipped: Set<String> = ["node_modules", "build", "dist", "target", "Pods", "DerivedData", "vendor", "__pycache__", "venv"]

    var vault: URL
    let home: Bool
    @ObservationIgnored let voiceHome: () -> URL
    var notes: [Note] = [] {
        didSet { editor?.titles(notes.map(\.title)) }
    }
    @ObservationIgnored private var scanning = false
    @ObservationIgnored private var rescan = false
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
    var sources: [URL] = []
    var focusID: Int?
    var model: ModelChoice?
    var models: [ModelChoice] = []
    @ObservationIgnored var showSettings: (Pane?) -> Void = { _ in }
    var mode: Mode {
        didSet { Prefs.mode = mode }
    }
    var crew: [String] = Prefs.crew {
        didSet { Prefs.crew = crew }
    }
    var agentID: String {
        didSet {
            guard agentID != oldValue else { return }
            Prefs.agent = agentID
            swapAgent()
        }
    }

    @ObservationIgnored weak var editor: Page?
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
    @ObservationIgnored private var places: [URL: (NSRange, Int, CGFloat)] = [:]
    @ObservationIgnored private var held: [Tell] = []
    @ObservationIgnored private var proposed = false
    @ObservationIgnored private var briefed: String?
    @ObservationIgnored var mates: [String: Agent] = [:]
    @ObservationIgnored private var matesBriefed: [String: String] = [:]
    @ObservationIgnored private var signed: String?
    @ObservationIgnored private var absent: [String] = []
    @ObservationIgnored lazy var keeper = VoiceKeeper(vault: home ? vault : voiceHome(), spec: spec)
    @ObservationIgnored let listener = Listener()
    @ObservationIgnored var turnStarted: CFAbsoluteTime = 0
    @ObservationIgnored var firstChangeAt: CFAbsoluteTime?

    init(vault: URL, home: Bool = true, voiceHome: @escaping () -> URL = { URL(fileURLWithPath: Prefs.vault ?? NSHomeDirectory() + "/Quill") }) {
        self.vault = vault
        self.home = home
        self.voiceHome = voiceHome
        desk = Workspace.desks.appending(path: Workspace.key(vault))
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

    var company: [AgentSpec] {
        crew.filter { $0 != agentID }.map(AgentSpec.named).filter { available($0) != false }
    }

    func toggle(mate id: String) {
        if crew.contains(id) {
            crew.removeAll { $0 == id }
            mates.removeValue(forKey: id)?.shutdown()
        } else {
            crew.append(id)
        }
    }

    var recommended: [ModelChoice] {
        var picks = spec.picks.compactMap { id in models.first { $0.id == id } }
        if picks.isEmpty { picks = Array(models.prefix(3)) }
        if let model, !picks.contains(model) { picks = Array(picks.prefix(2)) + [model] }
        return picks
    }

    func available(_ spec: AgentSpec) -> Bool? {
        switch spec.kind {
        case .api: return !Prefs.endpoint.isEmpty
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

    func attach(_ editor: Page) {
        self.editor = editor
        editor.titles(notes.map(\.title))
        editor.onPlayed = { [weak self] n in self?.finishedPlaying(n) }
        editor.onReview = { [weak self, weak editor] in
            guard let self, let editor, self.review != editor.review else { return }
            self.review = editor.review
            self.saveSoon()
        }
        editor.onResolve = { [weak self] hunks, outcome in self?.resolved(hunks, outcome) }
        editor.onUndo = { name, back in Ledger.event(back ? "undo" : "redo", detail: name) }
        editor.onOpenNote = { [weak self] link in self?.follow(link) }
        editor.onEmbed = { [weak self, weak editor] target in
            guard let self, let editor else { return }
            editor.embeds([target: Embeds.payload(target, from: current, root: vault, notes: notes)])
        }
    }

    func replace(_ agent: Agent) {
        self.agent.shutdown()
        self.agent = agent
    }

    func reconnect() {
        guard spec.api else { return }
        swapAgent()
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
            try? await agent.prepare(cwd: desk, readable: reachable)
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
        Files.roots.insert(vault.standardizedFileURL.path)
        Embeds.warm(vault)
        try? FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: desk, withIntermediateDirectories: true)
        watch()
        warm()
        checkAgents()
        keeper = VoiceKeeper(vault: home ? vault : voiceHome(), spec: spec)
        if home, !FileManager.default.fileExists(atPath: keeper.url.path) || Date.now.timeIntervalSince1970 - Prefs.measuredAt > 86_400 {
            Task { await measure() }
        }
        let last = (home ? Prefs.last : Prefs.last(in: vault.path)).map { URL(fileURLWithPath: $0) }
        refreshLater { [weak self] in
            guard let self, current == nil, let url = notes.first(where: { $0.url.path == last?.path })?.url ?? notes.first?.url else { return }
            open(url)
        }
    }

    func switchVault(_ url: URL) {
        endTurn()
        leave()
        unwatch()
        vault = url
        if home { Prefs.vault = url.path }
        current = nil
        editor?.load("")
        agent.shutdown()
        agent = spec.make()
        start()
    }

    var title: String {
        FileManager.default.displayName(atPath: vault.path)
    }

    var scope: String? {
        guard let current else { return nil }
        let folder = current.deletingLastPathComponent().standardizedFileURL.path
        let root = vault.standardizedFileURL.path
        guard folder == root || folder.hasPrefix(root + "/") else { return nil }
        let rest = folder.dropFirst(root.count).split(separator: "/").map(String.init)
        return ([title] + rest).joined(separator: " › ")
    }

    func refresh() {
        show(Self.scan(vault))
    }

    func refreshLater(then: (@MainActor @Sendable () -> Void)? = nil) {
        if scanning {
            rescan = true
            return
        }
        scanning = true
        let vault = vault
        Task.detached(priority: .userInitiated) {
            let found = Workspace.scan(vault)
            await MainActor.run { [weak self] in
                guard let self else { return }
                scanning = false
                if vault == self.vault { show(found) }
                then?()
                if rescan {
                    rescan = false
                    refreshLater()
                }
            }
        }
    }

    private func show(_ found: [Note]) {
        if found != notes { notes = found }
    }

    nonisolated static func scan(_ vault: URL) -> [Note] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        var found: [Note] = []
        let walker = FileManager.default.enumerator(at: vault, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants])
        while let url = walker?.nextObject() as? URL {
            if skipped.contains(url.lastPathComponent) {
                walker?.skipDescendants()
                continue
            }
            guard url.pathExtension.lowercased() == "md" else { continue }
            found.append(Note(url: url, modified: (try? url.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast))
        }
        return found.sorted { $0.modified > $1.modified }
    }

    func open(_ url: URL) {
        guard url != current else { return }
        endTurn()
        leave()
        margin = []
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        current = url
        if url.path.hasPrefix(vault.path + "/") {
            if home { Prefs.last = url.path } else { Prefs.setLast(url.path, in: vault.path) }
        }
        saved = text
        let (selection, top, shift) = places[url] ?? (NSRange(location: 0, length: 0), 0, 0)
        var found: [String: [String: Any]] = [:]
        for target in Embeds.targets(in: text) { found[target] = Embeds.payload(target, from: url, root: vault, notes: notes) }
        editor?.embeds(found, early: true)
        editor?.load(text, caret: NSMaxRange(selection) <= (text as NSString).length ? selection.location : 0, top: top, shift: shift)
        if case .failed = phase { phase = .idle }
    }

    private func leave() {
        editor?.land()
        settleReview()
        flushSave()
        guard let url = current, let editor else { return }
        places[url] = (editor.selectedRange(), editor.top, editor.shift)
        let name = url.deletingPathExtension().lastPathComponent
        guard name.wholeMatch(of: /Untitled( \d+)?/) != nil,
              let first = editor.text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first,
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
        resolved(hunks, .unreviewed)
    }

    func create(in folder: URL? = nil) {
        let folder = folder ?? vault
        var name = "Untitled"
        var n = 2
        while FileManager.default.fileExists(atPath: folder.appending(path: "\(name).md").path) {
            name = "Untitled \(n)"
            n += 1
        }
        let url = folder.appending(path: "\(name).md")
        try? "# \n".write(to: url, atomically: true, encoding: .utf8)
        notes.insert(Note(url: url, modified: .now), at: 0)
        open(url)
        editor?.setSelectedRange(NSRange(location: 2, length: 0))
        editor?.focus()
    }

    func mentions(_ token: Substring) -> [Mention] {
        let home = NSHomeDirectory()
        func mention(_ url: URL, folder: Bool) -> Mention {
            let path = url.path.hasPrefix(home + "/") ? String(url.path.dropFirst(home.count + 1)) : url.path
            return Mention(url: url, insert: path + (folder ? "/" : " "), folder: folder)
        }
        if let slash = token.lastIndex(of: "/") {
            let dir = located(String(token[..<slash]))
            let prefix = token[token.index(after: slash)...].lowercased()
            let keys: [URLResourceKey] = [.isDirectoryKey]
            let items = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
            return items
                .filter { prefix.isEmpty || $0.lastPathComponent.lowercased().hasPrefix(prefix) }
                .filter { browsable($0.path) }
                .map { mention($0, folder: (try? $0.resourceValues(forKeys: Set(keys)).isDirectory) == true) }
                .sorted { $0.folder != $1.folder ? $0.folder : $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending }
                .prefix(7).map { $0 }
        }
        let q = token.lowercased()
        let titled = notes.filter { q.isEmpty || $0.title.lowercased().contains(q) }
            .sorted { a, b in
                let pa = a.title.lowercased().hasPrefix(q), pb = b.title.lowercased().hasPrefix(q)
                return pa != pb ? pa : a.modified > b.modified
            }
            .prefix(q.isEmpty ? 5 : 4)
            .map { mention($0.url, folder: false) }
        guard !q.isEmpty else { return Array(titled) }
        let folders = ((try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: home), includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? [])
            .filter { $0.hasDirectoryPath && $0.lastPathComponent.lowercased().hasPrefix(q) && browsable($0.path) }
            .prefix(3)
            .map { mention($0, folder: true) }
        return Array(titled) + folders
    }

    func cite(_ path: String) {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let skip = [deskFile, keeper.url, Guide.skill].compactMap { $0?.standardizedFileURL.path }
        guard !skip.contains(where: { url.path == $0 || url.path.hasPrefix($0 + "/") }), !sources.contains(url) else { return }
        sources.append(url)
    }

    func reveal(_ url: URL) {
        if url.pathExtension.lowercased() == "md", url.path.hasPrefix(vault.path) { return open(url) }
        var folder: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &folder)
        if folder.boolValue { NSWorkspace.shared.activateFileViewerSelecting([url]) } else { NSWorkspace.shared.open(url) }
    }

    func follow(_ link: String) {
        let name = link.components(separatedBy: "#")[0].trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let path = name.lowercased().hasSuffix(".md") ? String(name.dropLast(3)) : name
        if let note = notes.first(where: { $0.title.caseInsensitiveCompare(path) == .orderedSame })
            ?? notes.first(where: { $0.url.path.lowercased().hasSuffix("/" + path.lowercased() + ".md") }) {
            return open(note.url)
        }
        let url = vault.appending(path: path.replacingOccurrences(of: ":", with: "-") + ".md")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? "# \(url.deletingPathExtension().lastPathComponent)\n\n".write(to: url, atomically: true, encoding: .utf8)
        notes.insert(Note(url: url, modified: .now), at: 0)
        open(url)
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
            notes = notes.map { $0.url == note.url ? Note(url: target, modified: $0.modified) : $0 }
            return nil
        } catch {
            return "Couldn't rename “\(note.title)”."
        }
    }

    func trash(_ note: Note) {
        if current == note.url {
            endTurn()
            current = nil
            editor?.load("")
        }
        try? FileManager.default.trashItem(at: note.url, resultingItemURL: nil)
        notes.removeAll { $0.url == note.url }
        if current == nil, let first = notes.first { open(first.url) }
    }

    func edited() {
        if !margin.isEmpty, let editor {
            let doc = editor.buffer
            let moved = margin.compactMap { note -> MarginNote? in
                var note = note
                note.range = doc.range(of: note.quote, options: [.caseInsensitive, .diacriticInsensitive])
                return note.range.location == NSNotFound ? nil : note
            }
            if moved != margin { margin = moved }
        }
        saveSoon()
    }

    private func saveSoon() {
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
        let text = editor.review.accepted(editor.text)
        guard text != saved else { return }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            saved = text
        } catch {
            fail("Couldn't save \(url.lastPathComponent).")
        }
    }

    private func whenIdle(_ then: @escaping () -> Void) -> Bool {
        guard editor?.isPlaying == true else { return false }
        guard settle == nil else { return true }
        settle = Task { [weak self] in
            while self?.editor?.isPlaying == true, !Task.isCancelled { try? await Task.sleep(for: .milliseconds(60)) }
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
        let changes = merge(base: saved, current: editor.text, proposed: disk)
        saved = disk
        editor.play(changes, as: .other, turn: 0)
    }

    func refreshEmbeds(_ changed: [String]) {
        guard let editor, let current else { return }
        let others = changed.map { URL(fileURLWithPath: $0) }.filter { $0.standardizedFileURL != current.standardizedFileURL && !$0.lastPathComponent.hasPrefix(".") }
        guard !others.isEmpty else { return }
        let names = Set(others.map { $0.deletingPathExtension().lastPathComponent.lowercased() })
        var found: [String: [String: Any]] = [:]
        for target in Embeds.targets(in: editor.text) {
            let file = (target.hasPrefix("path:") ? String(target.dropFirst(5)) : target).split(separator: "#").first.map(String.init) ?? target
            guard names.contains(URL(fileURLWithPath: file).deletingPathExtension().lastPathComponent.lowercased()) else { continue }
            found[target] = Embeds.payload(target, from: current, root: vault, notes: notes)
        }
        editor.embeds(found)
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
        let changes = merge(base: deskBase, current: editor.text, proposed: disk)
        deskBase = disk
        proposed = true
        guard !changes.isEmpty else { return }
        if firstChangeAt == nil { firstChangeAt = CFAbsoluteTimeGetCurrent() }
        phase = .applying(editor.review.turn(turn).count + changes.count)
        if let first = changes.first { editor.present(editor.paragraph(at: first.range.location)) }
        editor.play(changes, as: .agent(turn: turn, flags: flags, by: signed), turn: turn)
    }

    var reachable: [URL] { [vault] + voiceSources.filter { $0 != vault } + (Guide.skill.map { [$0] } ?? []) }

    var voiceSources: [URL] {
        let base = home ? vault : voiceHome()
        return [base] + Prefs.voiceSources.map { URL(fileURLWithPath: $0) }.filter { $0 != base }
    }

    nonisolated static func key(_ note: URL) -> String {
        var h: UInt64 = 1469598103934665603
        for b in note.standardizedFileURL.path.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return String(h, radix: 36)
    }

    @discardableResult
    func measure() async -> Fingerprint {
        let f = await keeper.measure(voiceSources)
        refreshLater()
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
        if editor.isPlaying {
            Task { [weak self] in
                await editor.settled()
                self?.ask(words, mode: override)
            }
            return
        }
        flushSave()
        let mode = override ?? self.mode
        let text = editor.text
        let title = url.deletingPathExtension().lastPathComponent
        let fm = FileManager.default
        for stale in (try? fm.contentsOfDirectory(at: desk, includingPropertiesForKeys: nil)) ?? [] { try? fm.removeItem(at: stale) }
        let room = desk.appending(path: Self.key(url))
        try? fm.createDirectory(at: room, withIntermediateDirectories: true)
        let file = room.appending(path: "\(title).md")
        do { try text.write(to: file, atomically: true, encoding: .utf8) } catch {
            fail("Couldn't prepare a working copy of \(title).")
            return
        }
        deskFile = file
        deskBase = text
        let sel = editor.selectedRange()
        let selection = sel.length > 0 ? (text as NSString).substring(with: sel) : nil
        let crewing = mode == .guided ? company : []
        let links = Links.found(in: [words, selection ?? "", text])
        var request = Request(words: words, title: title, path: file.path, text: text, selection: selection, mode: mode,
                              peers: crewing.map(\.name), folder: url.deletingLastPathComponent().path, root: vault.path)
        signed = crewing.isEmpty ? nil : spec.name
        absent = []
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
        sources = []
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
                if !links.isEmpty {
                    phase = .thinking(links.count == 1 ? "Reading the link" : "Reading \(links.count) links", words: words)
                    let pages = await Links.read(links)
                    request.sources = links.map { url in Request.Source(url: url.absoluteString, text: pages.first { $0.url == url }?.text ?? "") }
                    guard turn == id else { return }
                }
                let lead = spec.name
                let runs = crewing.map { mate in
                    Task { await self.run(mate, request, title: title, voice: voice, peers: [lead] + crewing.filter { $0 != mate }.map(\.name)) }
                }
                try await agent.prepare(cwd: desk, readable: reachable)
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
                        case .read(let path):
                            self.cite(path)
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
                if !runs.isEmpty {
                    phase = .thinking("Waiting for \(crewing.map(\.name).joined(separator: " and "))", words: words)
                    var versions: [(AgentSpec, String)] = []
                    for run in runs { if let v = await run.value { versions.append(v) } }
                    guard turn == id else { return }
                    await stackCrew(versions, original: text)
                }
            } catch {
                failure = error.localizedDescription
            }
            guard turn == id else { return }
            await settleTurn(id: id, url: url, failure: failure, words: words, mode: mode)
        }
    }

    private func run(_ mate: AgentSpec, _ request: Request, title: String, voice: String?, peers: [String]) async -> (AgentSpec, String)? {
        let fm = FileManager.default
        let dir = desk.appending(path: "crew/\(mate.id)")
        try? fm.removeItem(at: dir)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appending(path: "\(title).md")
        guard (try? request.text.write(to: file, atomically: true, encoding: .utf8)) != nil else { return nil }
        let agent = mates[mate.id] ?? mate.make()
        mates[mate.id] = agent
        var asked = request
        asked.path = file.path
        asked.peers = peers
        var version = request.text
        do {
            try await agent.prepare(cwd: dir, readable: reachable)
            let brief = agent.conversation == nil || agent.conversation != matesBriefed[mate.id]
            let body = prompt(asked, canEditFiles: agent.canEditFiles, voice: voice, briefing: brief ? Guide.briefing() : nil)
            try await agent.send(body, file: file, base: request.text) { event in
                if case .proposed(let next) = event { version = next }
            }
            matesBriefed[mate.id] = agent.conversation
        } catch {
            Ledger.event("crew-failed", detail: "\(mate.id): \(error.localizedDescription)")
            let why = error.localizedDescription.split(separator: ".").first.map { "\($0)." } ?? "it stopped."
            absent.append("\(mate.name) couldn't answer: \(why)")
            return nil
        }
        if agent.canEditFiles, let disk = try? String(contentsOf: file, encoding: .utf8) { version = disk }
        return version == request.text ? nil : (mate, version)
    }

    private func stackCrew(_ versions: [(AgentSpec, String)], original: String) async {
        reconcileDesk()
        while editor?.isPlaying == true || settle != nil { try? await Task.sleep(for: .milliseconds(50)) }
        guard let editor, !versions.isEmpty else { return }
        let combined = stack(base: original, versions: [deskBase] + versions.map(\.1))
        let changes = merge(base: deskBase, current: editor.text, proposed: combined)
        deskBase = combined
        if let deskFile { try? combined.write(to: deskFile, atomically: true, encoding: .utf8) }
        guard !changes.isEmpty else { return }
        proposed = true
        if firstChangeAt == nil { firstChangeAt = CFAbsoluteTimeGetCurrent() }
        let authors = changes.map { change -> String in
            let added = change.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return versions.first { !added.isEmpty && $0.1.contains(added) }?.0.name ?? versions[0].0.name
        }
        var placed: [Change] = []
        for name in versions.map(\.0.name) {
            let mine = zip(changes, authors).filter { $0.1 == name }.map(\.0)
            guard !mine.isEmpty else { continue }
            let moved = mine.map { c -> Change in
                let shift = placed.filter { $0.range.location < c.range.location }.reduce(0) { $0 + $1.text.utf16.count - $1.range.length }
                return Change(range: NSRange(location: c.range.location + shift, length: c.range.length), text: c.text)
            }
            phase = .applying(editor.review.turn(turn).count + moved.count)
            editor.play(moved, as: .agent(turn: turn, flags: [], by: name), turn: turn)
            while editor.isPlaying { try? await Task.sleep(for: .milliseconds(50)) }
            placed += mine
        }
    }

    private func settleTurn(id: Int, url: URL, failure: String?, words: String, mode: Mode) async {
        reconcileDesk()
        while editor?.isPlaying == true || settle != nil {
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
        let pending = editor?.review.turn(id).count ?? 0
        let said = crisp(readable(raw), sentences: pending > 0 ? 1 : 3)
        if mode == .notes || raw.contains("<notes>") || tagged != nil, let editor,
           let found = QuillCore.notes(from: tagged.map { "<notes>\($0)</notes>" } ?? raw, in: editor.text), !found.isEmpty {
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
        let full = ([absent.isEmpty ? said : summary] + absent).filter { !$0.isEmpty }.joined(separator: " ")
        transcript[url, default: []].append(Line(words: words, reply: absent.isEmpty ? summary : full))
        phase = full.isEmpty ? .done(pending) : .said(full)
    }

    private func focus(_ passage: String) {
        guard let editor else { return }
        let doc = editor.buffer as NSString
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
        let doc = NSString(string: editor.text)
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
        if editor.isPlaying {
            Task { [weak self] in
                await editor.settled()
                self?.keep(hunks)
            }
            return
        }
        editor.keep(hunks ?? editor.review.hunks)
        if editor.review.isEmpty, case .done = phase { phase = .idle }
    }

    func revert(_ hunks: [Hunk]? = nil) {
        guard let editor else { return }
        if editor.isPlaying {
            Task { [weak self] in
                await editor.settled()
                self?.revert(hunks)
            }
            return
        }
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
        editor.reveal(next.range)
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
        mates.values.forEach { $0.cancel() }
        let id = turn
        turn += 1
        settle?.cancel()
        settle = nil
        editor?.land()
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
        let paths = [vault.path, desk.path] as CFArray
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, flags, _ in
            guard let info else { return }
            let ws = Unmanaged<Workspace>.fromOpaque(info).takeUnretainedValue()
            let changed = (unsafeBitCast(paths, to: NSArray.self) as? [String]) ?? []
            let moved = UInt32(kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemRemoved | kFSEventStreamEventFlagItemRenamed)
            let lost = UInt32(kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped | kFSEventStreamEventFlagKernelDropped)
            let reshaped = (0..<count).filter { flags[$0] & moved != 0 && $0 < changed.count }.map { changed[$0] }
            let rescan = (0..<count).contains { flags[$0] & lost != 0 }
            let folder = UInt32(kFSEventStreamEventFlagItemIsDir)
            let listed = rescan || (0..<count).contains { i in
                guard i < changed.count else { return false }
                let url = URL(fileURLWithPath: changed[i])
                guard !url.pathComponents.contains(where: { $0.hasPrefix(".") || Workspace.skipped.contains($0) }) else { return false }
                return url.pathExtension.lowercased() == "md" || (flags[i] & folder != 0 && flags[i] & moved != 0)
            }
            MainActor.assumeIsolated {
                if rescan { Embeds.forget(ws.vault) } else { Embeds.noticed(reshaped, root: ws.vault) }
                let desk = ws.desk.resolvingSymlinksInPath().path
                if changed.contains(where: { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path.hasPrefix(desk) }) { ws.reconcileDesk() }
                if changed.contains(where: { !URL(fileURLWithPath: $0).resolvingSymlinksInPath().path.hasPrefix(desk) }) {
                    ws.reconcileVault()
                    if listed { ws.refreshLater() }
                    ws.refreshEmbeds(changed)
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
