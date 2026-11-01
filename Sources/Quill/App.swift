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
    var selectedWords = 0
    var history: [String] = UserDefaults.standard.stringArray(forKey: "history") ?? []
    var recall: Int?

    func remember(_ words: String) {
        history.removeAll { $0 == words }
        history.append(words)
        history = Array(history.suffix(30))
        recall = nil
        UserDefaults.standard.set(history, forKey: "history")
    }
}

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static func main() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--transcribe"), i + 1 < args.count {
            let file = URL(fileURLWithPath: args[i + 1])
            Task { @MainActor in
                let start = CFAbsoluteTimeGetCurrent()
                do {
                    let text = try await Listener().transcribe(file: file)
                    print(String(format: "%.2fs\t%@", CFAbsoluteTimeGetCurrent() - start, text))
                    exit(0)
                } catch {
                    print("error: \(error)")
                    exit(1)
                }
            }
            RunLoop.main.run()
        }
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
        ws.showSettings = { [weak self] in self?.openSettings() }
        if fresh { seed(vault) }

        editor = EditorController(ws: ws)
        let split = NSSplitViewController()
        let side = NSSplitViewItem(sidebarWithViewController: NSHostingController(rootView: Sidebar(ws: ws, settings: { [weak self] in self?.openSettings() })))
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
        ws.quit()
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
        func item(_ title: String, _ action: Selector?, _ key: String = "", _ mods: NSEvent.ModifierFlags = .command, target: AnyObject? = nil, tag: Int = 0) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
            i.keyEquivalentModifierMask = mods
            i.target = target
            i.tag = tag
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
        func find(_ title: String, _ key: String, _ mods: NSEvent.ModifierFlags, _ action: NSFindPanelAction) -> NSMenuItem {
            item(title, #selector(NSTextView.performFindPanelAction(_:)), key, mods, tag: Int(action.rawValue))
        }

        let services = NSMenu()
        NSApp.servicesMenu = services
        let servicesItem = item("Services", nil)
        servicesItem.submenu = services
        _ = add("Quill", [
            item("About Quill", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            .separator(),
            item("Settings…", #selector(openSettings), ",", target: self),
            .separator(),
            servicesItem,
            .separator(),
            item("Hide Quill", #selector(NSApplication.hide(_:)), "h"),
            item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            item("Show All", #selector(NSApplication.unhideAllApplications(_:))),
            .separator(),
            item("Quit Quill", #selector(NSApplication.terminate(_:)), "q"),
        ])
        _ = add("File", [
            item("New Note", #selector(newNote), "n", target: self),
            item("Open Folder…", #selector(openFolder), "o", target: self),
            .separator(),
            item("Save", #selector(save), "s", target: self),
            item("Rename…", #selector(rename), "", target: self),
            item("Show in Finder", #selector(reveal), "r", [.command, .option], target: self),
            .separator(),
            item("Move to Trash", #selector(trash), target: self),
            .separator(),
            item("Close Window", #selector(NSWindow.performClose(_:)), "w"),
        ])
        let findMenu = NSMenu(title: "Find")
        [
            find("Find…", "f", .command, .showFindPanel),
            find("Find and Replace…", "f", [.command, .option], .init(rawValue: 12)!),
            find("Find Next", "g", .command, .next),
            find("Find Previous", "g", [.command, .shift], .previous),
            find("Use Selection for Find", "e", .command, .setFindString),
            item("Jump to Selection", #selector(NSResponder.centerSelectionInVisibleArea(_:)), "j"),
        ].forEach(findMenu.addItem)
        let findItem = item("Find", nil)
        findItem.submenu = findMenu
        _ = add("Edit", [
            item("Undo", Selector(("undo:")), "z"),
            item("Redo", Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            item("Cut", #selector(NSText.cut(_:)), "x"),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            item("Paste and Match Style", #selector(NSTextView.pasteAsPlainText(_:)), "v", [.command, .option, .shift]),
            item("Delete", #selector(NSText.delete(_:))),
            item("Select All", #selector(NSText.selectAll(_:)), "a"),
            .separator(),
            findItem,
        ])
        _ = add("Format", [
            item("Bold", #selector(QuillTextView.bold(_:)), "b"),
            item("Italic", #selector(QuillTextView.italic(_:)), "i"),
            item("Strikethrough", #selector(QuillTextView.strike(_:)), "x", [.command, .shift]),
            item("Code", #selector(QuillTextView.code(_:)), "c", [.command, .option]),
            .separator(),
            item("Heading 1", #selector(QuillTextView.heading(_:)), "1", tag: 1),
            item("Heading 2", #selector(QuillTextView.heading(_:)), "2", tag: 2),
            item("Heading 3", #selector(QuillTextView.heading(_:)), "3", tag: 3),
            item("Body Text", #selector(QuillTextView.heading(_:)), "0", tag: 0),
        ])
        let agents = NSMenu(title: "Co-writer")
        for (i, spec) in AgentSpec.all.enumerated() {
            agents.addItem(item(spec.name, #selector(chooseAgent(_:)), target: self, tag: i))
        }
        agents.addItem(.separator())
        agents.addItem(item("Settings…", #selector(openSettings), target: self))
        let agentsItem = item("Co-writer", nil)
        agentsItem.submenu = agents
        let talk = item("Hold Right ⌥ to Talk", nil)
        talk.isEnabled = false
        _ = add("Agent", [
            item("Ask…", #selector(ask), "k", target: self),
            talk,
            item("Stop", #selector(stop), ".", target: self),
            .separator(),
            item("Guided Edits", #selector(guided), "1", [.command, .control], target: self),
            item("Margin Notes", #selector(notesMode), "2", [.command, .control], target: self),
            .separator(),
            agentsItem,
        ])
        _ = add("View", [
            item("Hide Sidebar", #selector(NSSplitViewController.toggleSidebar(_:)), "s", [.command, .control]),
            .separator(),
            item("Actual Size", #selector(EditorController.actualSize(_:)), "0", [.command, .option]),
            item("Zoom In", #selector(EditorController.zoomIn(_:)), "+"),
            item("Zoom Out", #selector(EditorController.zoomOut(_:)), "-"),
            .separator(),
            item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]),
        ])
        let windowMenu = add("Window", [
            item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
            item("Zoom", #selector(NSWindow.performZoom(_:))),
            .separator(),
            item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))),
        ])
        NSApp.windowsMenu = windowMenu
        NSApp.helpMenu = add("Help", [
            item("Welcome to Quill", #selector(welcome), target: self),
        ])
        return bar
    }

    @objc private func newNote() { ws.create() }
    @objc private func ask() { editor.command() }
    @objc private func stop() { ws.cancelTurn() }
    @objc private func guided() { ws.mode = .guided }
    @objc private func notesMode() { ws.mode = .notes }
    @objc private func save() { ws.flushSave() }
    @objc private func chooseAgent(_ sender: NSMenuItem) { ws.agentID = AgentSpec.all[sender.tag].id }
    @objc private func reveal() {
        NSWorkspace.shared.activateFileViewerSelecting([ws.current ?? ws.vault])
    }

    @objc private func rename() {
        guard let note = ws.notes.first(where: { $0.url == ws.current }) else { return }
        let alert = NSAlert()
        alert.messageText = "Rename note"
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(string: note.title)
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { [weak self] r in
            guard r == .alertFirstButtonReturn, let self, let problem = self.ws.rename(note, to: field.stringValue) else { return }
            self.ws.phase = .failed(problem)
        }
    }

    @objc private func trash() {
        guard let note = ws.notes.first(where: { $0.url == ws.current }) else { return }
        ws.trash(note)
    }

    @objc private func welcome() {
        let url = ws.vault.appending(path: "Welcome.md")
        if !FileManager.default.fileExists(atPath: url.path) {
            seed(ws.vault)
            ws.refresh()
        }
        ws.open(url)
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
        switch item.action {
        case #selector(guided): item.state = ws.mode == .guided ? .on : .off
        case #selector(notesMode): item.state = ws.mode == .notes ? .on : .off
        case #selector(chooseAgent(_:)):
            let spec = AgentSpec.all[item.tag]
            item.state = ws.agentID == spec.id ? .on : .off
        case #selector(stop):
            if case .idle = ws.phase { return ws.listener.isListening }
        case #selector(ask), #selector(rename), #selector(trash), #selector(save):
            return ws.current != nil
        default: break
        }
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

        let empty = NSHostingView(rootView: EmptyState(ws: ws))
        empty.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(empty)

        let pill = NSHostingView(rootView: Pill(ws: ws, chrome: chrome))
        pill.translatesAutoresizingMaskIntoConstraints = false
        pill.sizingOptions = [.intrinsicContentSize]
        root.addSubview(pill)

        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: root.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            empty.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            empty.centerYAnchor.constraint(equalTo: root.centerYAnchor, constant: -40),
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
        scroll.allowsMagnification = true
        scroll.minMagnification = 0.7
        scroll.maxMagnification = 2
        let zoom = UserDefaults.standard.double(forKey: "zoom")
        if zoom > 0 { scroll.magnification = zoom }
        NotificationCenter.default.addObserver(forName: NSScrollView.didEndLiveMagnifyNotification, object: scroll, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.remember() }
        }
        observe()
        listen()
    }

    @objc func zoomIn(_ sender: Any?) { zoom(scroll.magnification * 1.1) }
    @objc func zoomOut(_ sender: Any?) { zoom(scroll.magnification / 1.1) }
    @objc func actualSize(_ sender: Any?) { zoom(1) }

    private func zoom(_ value: CGFloat) {
        let clamped = min(scroll.maxMagnification, max(scroll.minMagnification, value))
        let caret = text.segments(NSRange(location: text.selectedRange().location, length: 0)).first
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
            if let caret {
                scroll.animator().setMagnification(clamped, centeredAt: CGPoint(x: caret.midX, y: caret.midY))
            } else {
                scroll.animator().magnification = clamped
            }
        }
        UserDefaults.standard.set(clamped, forKey: "zoom")
    }

    private func remember() {
        UserDefaults.standard.set(scroll.magnification, forKey: "zoom")
    }

    private func observe() {
        withObservationTracking {
            _ = ws.margin
            _ = ws.phase
            _ = ws.current
            _ = chrome.commanding
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.title()
                self.announce()
                if !self.chrome.commanding, self.view.window?.firstResponder !== self.text {
                    self.view.window?.makeFirstResponder(self.text)
                }
                self.layoutNotes()
                self.afterTurn()
                self.observe()
            }
        }
    }

    private func title() {
        guard let window = view.window else { return }
        window.title = ws.current?.deletingPathExtension().lastPathComponent ?? ""
        window.representedURL = ws.current
        text.isEditable = ws.current != nil
    }

    private var spoken: Phase = .idle
    private func announce() {
        guard ws.phase != spoken else { return }
        spoken = ws.phase
        let line: String? = switch ws.phase {
        case .done(let n): n == 0 ? "Nothing to change" : n == 1 ? "1 change. Command Z to undo." : "\(n) changes. Command Z to undo."
        case .said(let s): s
        case .failed(let s): s
        case .thinking: "Working"
        default: nil
        }
        guard let line else { return }
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: line, .priority: NSAccessibilityPriorityLevel.high.rawValue])
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
        if !chrome.commanding {
            let sel = text.selectedRange()
            chrome.selectedWords = sel.length == 0 ? 0 : (text.string as NSString).substring(with: sel).split(whereSeparator: \.isWhitespace).count
            chrome.recall = nil
        }
        chrome.commanding.toggle()
    }

    private func listen() {
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.holding else { return }
                self.holding = false
                self.ws.listener.cancel()
                self.ws.phase = .idle
            }
        }
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
            let rightOption: UInt = 0x40
            let down = event.modifierFlags.rawValue & rightOption != 0 && event.modifierFlags.intersection([.command, .control, .shift]).isEmpty
            if down, !self.holding { self.press() } else if !down, self.holding { self.release() }
            return event
        }
    }

    private func press() {
        guard !isThinking(ws.phase) else { return }
        holding = true
        chord = false
        chrome.commanding = false
        ws.choreographer?.land()
        Task {
            guard await Listener.authorize() else {
                ws.fail("Quill needs the microphone to hear you.", remedy: ("Open Settings", {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
                }))
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
            let y = max((text.segments(note.range).first?.minY ?? 0) + 7, floor)
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
    var settings: () -> Void = {}
    @State private var renaming: Note?
    @State private var name = ""

    var body: some View {
        VStack(spacing: 0) {
            List(selection: Binding(get: { ws.current }, set: { if let url = $0 { ws.open(url) } })) {
                Section {
                    ForEach(ws.notes) { note in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(note.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                            TimelineView(.everyMinute) { _ in
                                Text(note.modified, format: .relative(presentation: .named))
                            }
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
            AgentBadge(ws: ws, settings: settings)
        }
        .alert("Rename note", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $name)
            Button("Rename") {
                if let r = renaming, let problem = ws.rename(r, to: name) { ws.phase = .failed(problem) }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }
}

struct EmptyState: View {
    var ws: Workspace
    var body: some View {
        if ws.current == nil {
            VStack(spacing: 10) {
                Text(ws.notes.isEmpty ? "No notes yet" : "No note open")
                    .font(.serif(22, .semibold)).foregroundStyle(Color.ink)
                Button { ws.create() } label: {
                    HStack(spacing: 6) { Text("New note"); Keycap("⌘N") }
                }
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Color.soft)
            }
        }
    }
}

struct AgentBadge: View {
    @Bindable var ws: Workspace
    var settings: () -> Void
    @State private var hovering = false

    private var state: (Color, String?) {
        switch ws.phase {
        case .listening: return (.accentInk, "Listening")
        case .thinking, .applying: return (.accentInk, "Working")
        case .failed: return (.redInk, "Needs attention")
        default: break
        }
        switch ws.available(ws.spec) {
        case true?: return (.soft, nil)
        case false?: return (.redInk, ws.spec.requires == nil ? "Needs a key" : ws.spec.requires == "npx" ? "Needs Node" : "Not installed")
        case nil: return (.faint, nil)
        }
    }

    var body: some View {
        let (dot, note) = state
        Menu {
            Picker("Co-writer", selection: $ws.agentID) {
                ForEach(AgentSpec.all) { spec in
                    Text(spec.name).tag(spec.id)
                }
            }
            .pickerStyle(.inline)
            Picker("Answer with", selection: $ws.mode) {
                Text("Guided Edits").tag(Mode.guided)
                Text("Margin Notes").tag(Mode.notes)
            }
            .pickerStyle(.inline)
            Divider()
            Button("Settings…", action: settings)
        } label: {
            HStack(spacing: 8) {
                Circle().fill(dot).frame(width: 6, height: 6)
                VStack(alignment: .leading, spacing: 1) {
                    Text(ws.spec.name).font(.system(size: 12, weight: .medium)).foregroundStyle(Color.ink)
                    Text(note ?? (ws.mode == .guided ? "Guided edits" : "Margin notes"))
                        .font(.system(size: 11)).foregroundStyle(note == nil ? Color.soft : dot)
                }
                .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.soft)
                    .opacity(hovering ? 1 : 0.6)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.ink.opacity(hovering ? 0.06 : 0)))
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
        .help("Co-writer and how it answers")
        .accessibilityLabel("\(ws.spec.name), \(note ?? (ws.mode == .guided ? "guided edits" : "margin notes"))")
    }
}

struct SettingsView: View {
    @Bindable var ws: Workspace
    @State private var key = Keychain.read("anthropic") ?? ""

    var body: some View {
        Form {
            Section("Co-writer") {
                ForEach(AgentSpec.all) { spec in
                    row(spec)
                }
            }
            Section {
                SecureField("API key", text: $key, prompt: Text("sk-ant-…"))
                    .onChange(of: key) {
                        Keychain.write("anthropic", key)
                        ws.hasKey = Keychain.anthropicKey?.isEmpty == false
                    }
            } header: {
                Text("Anthropic API")
            } footer: {
                Text("Stored in your Keychain. Used only when Anthropic API is the co-writer.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Section("Answers") {
                Picker("Answer with", selection: $ws.mode) {
                    Text("Guided Edits").tag(Mode.guided)
                    Text("Margin Notes").tag(Mode.notes)
                }
                .pickerStyle(.radioGroup)
                Text(ws.mode == .guided
                     ? "Quill edits the text while you watch. One ⌘Z takes a turn back."
                     : "Quill leaves notes in the margin. Click a note to apply it.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .tint(Color.accentInk)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { ws.checkAgents() }
    }

    private func row(_ spec: AgentSpec) -> some View {
        let available = ws.available(spec)
        let chosen = ws.agentID == spec.id
        return HStack(spacing: 10) {
            Image(systemName: chosen ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(chosen ? Color.accentInk : Color.soft)
            VStack(alignment: .leading, spacing: 1) {
                Text(spec.name).font(.system(size: 13, weight: .medium))
                Text(spec.detail).font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            Spacer()
            switch available {
            case true?:
                Text("Ready").font(.system(size: 11)).foregroundStyle(Color.greenInk)
            case false?:
                Text(spec.requires == nil ? "Needs a key" : spec.requires == "npx" ? "Needs Node" : "Not installed")
                    .font(.system(size: 11)).foregroundStyle(Color.soft)
            case nil:
                ProgressView().controlSize(.mini)
            }
        }
        .opacity(available == false && !chosen ? 0.55 : 1)
        .contentShape(Rectangle())
        .onTapGesture { ws.agentID = spec.id }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
    }
}
