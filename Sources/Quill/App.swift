import AppKit
import SwiftUI
import QuillCore

@MainActor
@Observable
final class Chrome {
    var commanding = false
    var draft = ""
    var hinting = !UserDefaults.standard.bool(forKey: "spoke")
    var choosingMode = false
}

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }

    private var window: NSWindow!
    private var settings: NSWindow?
    private var ws: Workspace!
    private var editor: EditorController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let env = ProcessInfo.processInfo.environment
        let saved = UserDefaults.standard.string(forKey: "vault")
        let vault = URL(fileURLWithPath: env["QUILL_VAULT"] ?? saved ?? NSHomeDirectory() + "/Quill")
        let fresh = !FileManager.default.fileExists(atPath: vault.path)
        ws = Workspace(vault: vault)
        if fresh { seed(vault) }

        editor = EditorController(ws: ws)
        let split = NSSplitViewController()
        let side = NSSplitViewItem(sidebarWithViewController: NSHostingController(rootView: Sidebar(ws: ws)))
        side.minimumThickness = 210
        side.maximumThickness = 320
        side.canCollapse = true
        split.addSplitViewItem(side)
        let main = NSSplitViewItem(viewController: editor)
        main.titlebarSeparatorStyle = .none
        split.addSplitViewItem(main)

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1240, height: 820),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.contentViewController = split
        window.setContentSize(NSSize(width: 1240, height: 820))
        window.minSize = NSSize(width: 640, height: 420)
        window.setFrameAutosaveName("Quill")
        if window.frame.origin == .zero { window.center() }
        window.backgroundColor = Theme.paper
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(editor.text)

        NSApp.mainMenu = menu()
        ws.start()
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        ws.choreographer?.land()
        ws.flushSave()
    }

    private func seed(_ vault: URL) {
        try? FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        let welcome = """
        # Welcome to Quill

        Quill is a quiet place to write, with a co-writer who listens. Your notes are plain Markdown files in a folder on your Mac, so they open anywhere.

        ## Try it

        Here is a pitch with a weak opening. Hold the **right ⌥** key, say *"make the first sentence confident and short"*, then let go.

        > We are basically trying to kind of build a tool that maybe helps people write better, in a way.

        Writers lose hours to editing. Quill gives them an editor that listens, then shows its work: every change lands in front of you, and one ⌘Z takes it all back.

        ## Good to know

        - Press ⌘K to type a request instead of speaking.
        - Select a passage first and "this" means that passage.
        - Ask *"what do you think?"* for an opinion without edits.
        """
        try? welcome.write(to: vault.appending(path: "Welcome.md"), atomically: true, encoding: .utf8)
    }

    private func menu() -> NSMenu {
        let bar = NSMenu()
        func item(_ title: String, _ action: Selector?, _ key: String = "", _ mods: NSEvent.ModifierFlags = .command, target: AnyObject? = nil) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
            i.keyEquivalentModifierMask = mods
            i.target = target
            return i
        }
        func add(_ title: String, _ items: [NSMenuItem]) -> NSMenu {
            let m = NSMenu(title: title)
            items.forEach(m.addItem)
            let top = NSMenuItem()
            top.submenu = m
            bar.addItem(top)
            return m
        }

        _ = add("Quill", [
            item("About Quill", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            .separator(),
            item("Settings…", #selector(openSettings), ",", target: self),
            .separator(),
            item("Hide Quill", #selector(NSApplication.hide(_:)), "h"),
            item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            .separator(),
            item("Quit Quill", #selector(NSApplication.terminate(_:)), "q"),
        ])
        _ = add("File", [
            item("New Note", #selector(newNote), "n", target: self),
            item("Open Folder…", #selector(openFolder), "o", target: self),
            item("Show in Finder", #selector(reveal), "r", [.command, .option], target: self),
            .separator(),
            item("Close Window", #selector(NSWindow.performClose(_:)), "w"),
        ])
        _ = add("Edit", [
            item("Undo", Selector(("undo:")), "z"),
            item("Redo", Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            item("Cut", #selector(NSText.cut(_:)), "x"),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            item("Paste and Match Style", #selector(NSTextView.pasteAsPlainText(_:)), "v", [.command, .option, .shift]),
            item("Select All", #selector(NSText.selectAll(_:)), "a"),
            .separator(),
            {
                let i = item("Find…", #selector(NSTextView.performFindPanelAction(_:)), "f")
                i.tag = Int(NSFindPanelAction.showFindPanel.rawValue)
                return i
            }(),
            {
                let i = item("Find Next", #selector(NSTextView.performFindPanelAction(_:)), "g")
                i.tag = Int(NSFindPanelAction.next.rawValue)
                return i
            }(),
        ])
        _ = add("Agent", [
            item("Ask…", #selector(ask), "k", target: self),
            item("Stop", #selector(stop), ".", target: self),
            .separator(),
            item("Guided Edits", #selector(guided), "1", [.command, .control], target: self),
            item("Margin Notes", #selector(notesMode), "2", [.command, .control], target: self),
            .separator(),
            item("Choose Agent…", #selector(openSettings), "", target: self),
        ])
        _ = add("View", [
            item("Toggle Sidebar", #selector(NSSplitViewController.toggleSidebar(_:)), "s", [.command, .control]),
            item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]),
        ])
        let windowMenu = add("Window", [
            item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
            item("Zoom", #selector(NSWindow.performZoom(_:))),
        ])
        NSApp.windowsMenu = windowMenu
        return bar
    }

    @objc private func newNote() { ws.create() }
    @objc private func ask() { editor.command() }
    @objc private func stop() { ws.cancelTurn() }
    @objc private func guided() { ws.mode = .guided }
    @objc private func notesMode() { ws.mode = .notes }
    @objc private func reveal() {
        NSWorkspace.shared.activateFileViewerSelecting([ws.current ?? ws.vault])
    }

    @objc private func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Open"
        panel.directoryURL = ws.vault
        panel.beginSheetModal(for: window) { [weak self] r in
            guard r == .OK, let url = panel.url else { return }
            self?.ws.switchVault(url)
        }
    }

    @objc private func openSettings() {
        if settings == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(ws: ws)))
            w.title = "Settings"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            settings = w
        }
        settings?.makeKeyAndOrderFront(nil)
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(guided) { item.state = ws.mode == .guided ? .on : .off }
        if item.action == #selector(notesMode) { item.state = ws.mode == .notes ? .on : .off }
        return true
    }
}

extension AppDelegate: NSMenuItemValidation {}

@MainActor
final class EditorController: NSViewController {
    let ws: Workspace
    let chrome = Chrome()
    private(set) var text: QuillTextView!
    private var scroll: NSScrollView!
    private var cards: [Int: NSHostingView<NoteCard>] = [:]
    private var activeNote: Int?
    private var monitor: Any?
    private var holding = false
    private var chord = false

    init(ws: Workspace) {
        self.ws = ws
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        (scroll, text) = QuillTextView.make()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(scroll)

        let pill = NSHostingView(rootView: Pill(ws: ws, chrome: chrome))
        pill.translatesAutoresizingMaskIntoConstraints = false
        pill.sizingOptions = [.intrinsicContentSize]
        root.addSubview(pill)

        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: root.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            pill.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            pill.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            pill.widthAnchor.constraint(lessThanOrEqualTo: root.widthAnchor, constant: -32),
        ])
        view = root

        let choreographer = Choreographer(view: text)
        choreographer.onFinish = { [weak self] n in self?.ws.finishedPlaying(n) }
        ws.editor = text
        ws.choreographer = choreographer
        text.onEdit = { [weak self] in
            self?.ws.edited()
            self?.layoutNotes()
        }
        text.beforeKey = { [weak choreographer] in choreographer?.land() }
        NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: text, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.layoutNotes() }
        }
        observe()
        listen()
    }

    private func observe() {
        withObservationTracking {
            _ = ws.margin
            _ = ws.phase
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.layoutNotes()
                self.afterTurn()
                self.observe()
            }
        }
    }

    private func afterTurn() {
        switch ws.phase {
        case .said, .done:
            if chrome.hinting {
                chrome.hinting = false
                UserDefaults.standard.set(true, forKey: "spoke")
            }
            if !UserDefaults.standard.bool(forKey: "choseMode") { chrome.choosingMode = true }
        case .listening, .thinking:
            chrome.choosingMode = false
        default:
            break
        }
    }

    func command() {
        guard !ws.listener.isListening else { return }
        chrome.commanding.toggle()
    }

    private func listen() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            guard let self, event.window == self.view.window else { return event }
            if event.type == .keyDown {
                if self.holding { self.chord = true; self.ws.cancelTurn(); self.holding = false }
                if event.keyCode == 53 {
                    if self.chrome.commanding { self.chrome.commanding = false; return nil }
                    if self.chrome.choosingMode { self.chrome.choosingMode = false; return nil }
                    switch self.ws.phase {
                    case .idle: break
                    case .thinking: self.ws.cancelTurn(); return nil
                    default: self.ws.phase = .idle; return nil
                    }
                }
                return event
            }
            guard event.keyCode == 61 else { return event }
            let down = event.modifierFlags.contains(.option) && event.modifierFlags.intersection([.command, .control, .shift]).isEmpty
            if down, !self.holding { self.press() } else if !down, self.holding { self.release() }
            return event
        }
    }

    private func press() {
        guard case let phase = ws.phase, !isThinking(phase) else { return }
        holding = true
        chord = false
        chrome.commanding = false
        ws.choreographer?.land()
        Task {
            guard await Listener.authorize() else {
                ws.phase = .failed("Quill needs the microphone. Allow it in System Settings → Privacy & Security.")
                holding = false
                return
            }
            guard holding else { return }
            ws.phase = .listening("")
            do { try await ws.listener.start() } catch {
                ws.phase = .failed("Couldn't start listening: \(error.localizedDescription)")
                holding = false
            }
        }
    }

    private func release() {
        holding = false
        guard !chord else { return }
        Task {
            let words = await ws.listener.stop()
            guard !chord else { return }
            if words.isEmpty {
                ws.phase = .idle
            } else {
                ws.ask(words)
            }
        }
    }

    private func isThinking(_ p: Phase) -> Bool {
        if case .thinking = p { return true }
        if case .applying = p { return true }
        return false
    }

    private func layoutNotes() {
        let margin = ws.margin
        let wanted = Set(margin.map(\.id))
        for (id, card) in cards where !wanted.contains(id) {
            card.removeFromSuperview()
            cards[id] = nil
        }
        let all = NSRange(location: 0, length: (text.string as NSString).length)
        text.clearMarks(.underlineColor)
        text.gutter = !margin.isEmpty
        guard !margin.isEmpty else { return }
        let x = text.textContainerInset.width + (text.textContainer?.size.width ?? Theme.column) + 40
        var floor: CGFloat = 0
        for note in margin {
            guard NSMaxRange(note.range) <= all.length else { continue }
            var look: [NSAttributedString.Key: Any] = [
                .underlineStyle: NSUnderlineStyle([.single, .patternDot]).rawValue,
                .underlineColor: Theme.accent.withAlphaComponent(0.75),
            ]
            if activeNote == note.id { look[.backgroundColor] = Theme.accent.withAlphaComponent(0.14) }
            text.mark(note.range, look)
            let card = cards[note.id] ?? {
                let h = NSHostingView(rootView: NoteCard(note: note, active: false, apply: {}, dismiss: {}, hover: { _ in }))
                h.sizingOptions = [.intrinsicContentSize]
                text.addSubview(h)
                cards[note.id] = h
                return h
            }()
            card.rootView = NoteCard(
                note: note,
                active: activeNote == note.id,
                apply: { [weak self] in self?.apply(note) },
                dismiss: { [weak self] in self?.ws.margin.removeAll { $0.id == note.id } },
                hover: { [weak self] on in
                    guard let self else { return }
                    let next = on ? note.id : (self.activeNote == note.id ? nil : self.activeNote)
                    if next != self.activeNote { self.activeNote = next; self.layoutNotes() }
                }
            )
            let size = card.fittingSize
            let y = max(text.segments(note.range).first?.minY ?? 0, floor)
            card.frame = CGRect(x: x, y: y, width: 220, height: size.height)
            floor = y + size.height + 14
        }
    }

    private func apply(_ note: MarginNote) {
        ws.margin.removeAll { $0.id == note.id }
        let mode = ws.mode
        ws.mode = .guided
        ws.ask("Apply your note about \"\(note.quote)\": \(note.note)")
        ws.mode = mode
    }
}

struct Sidebar: View {
    @Bindable var ws: Workspace
    @State private var renaming: Note?
    @State private var name = ""

    var body: some View {
        VStack(spacing: 0) {
            List(selection: Binding(get: { ws.current }, set: { if let url = $0 { ws.open(url) } })) {
                Section {
                    ForEach(ws.notes) { note in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(note.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                            Text(note.modified, format: .relative(presentation: .named))
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                        .tag(note.url)
                        .contextMenu {
                            Button("Rename…") { name = note.title; renaming = note }
                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([note.url]) }
                            Divider()
                            Button("Move to Trash", role: .destructive) { ws.trash(note) }
                        }
                    }
                } header: {
                    HStack {
                        Text(ws.vault.lastPathComponent)
                        Spacer()
                        Button { ws.create() } label: { Image(systemName: "square.and.pencil") }
                            .buttonStyle(.plain).help("New note (⌘N)")
                    }
                }
            }
            .listStyle(.sidebar)
            AgentBadge(ws: ws)
        }
        .alert("Rename note", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $name)
            Button("Rename") { if let r = renaming { ws.rename(r, to: name) }; renaming = nil }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }
}

struct AgentBadge: View {
    @Bindable var ws: Workspace
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(Color.greenInk).frame(width: 6, height: 6)
            Text(ws.spec.name).font(.system(size: 12, weight: .medium)).lineLimit(1).fixedSize()
            Spacer()
            Picker("", selection: $ws.mode) {
                Text("Guided").tag(Mode.guided)
                Text("Notes").tag(Mode.notes)
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .frame(width: 112)
            .labelsHidden()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

struct SettingsView: View {
    @Bindable var ws: Workspace
    @State private var key = Keychain.read("anthropic") ?? ""
    @State private var present: [String: Bool] = [:]

    var body: some View {
        Form {
            Section("Co-writer") {
                ForEach(AgentSpec.all) { spec in
                    let available = spec.requires.map { present[$0] ?? false } ?? !key.isEmpty || Keychain.anthropicKey != nil
                    HStack(spacing: 10) {
                        Image(systemName: ws.agentID == spec.id ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(ws.agentID == spec.id ? Color.accentInk : Color.soft)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(spec.name).font(.system(size: 13, weight: .medium))
                            Text(spec.detail).font(.system(size: 11.5)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(available ? "Ready" : spec.requires == nil ? "Needs a key" : "Not installed")
                            .font(.system(size: 11)).foregroundStyle(available ? Color.greenInk : Color.soft)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { ws.agentID = spec.id }
                }
            }
            Section("Anthropic API key") {
                SecureField("sk-ant-…", text: $key)
                    .onSubmit { Keychain.write("anthropic", key) }
                    .onChange(of: key) { Keychain.write("anthropic", key) }
                Text("Stored in your Keychain. Only used when Anthropic API is the co-writer.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Section("Answers") {
                Picker("Default", selection: $ws.mode) {
                    Text("Guided edits").tag(Mode.guided)
                    Text("Margin notes").tag(Mode.notes)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .task {
            for spec in AgentSpec.all {
                if let r = spec.requires { present[r] = await installed(r) }
            }
        }
    }
}
