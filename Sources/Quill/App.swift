import AppKit
import SwiftUI
import QuillCore

@MainActor
@Observable
final class Chrome {
    var commanding = false
    var draft = ""
    var hinting = !Prefs.spoke
    var selectedWords = 0
    var coach: String?
    var history: [String] = Prefs.history
    var recall: Int?
    var stash = ""
    var searching = false
    var talkKey = Prefs.talkKey {
        didSet { Prefs.talkKey = talkKey }
    }

    func remember(_ words: String) {
        history.removeAll { $0 == words }
        history.append(words)
        history = Array(history.suffix(30))
        recall = nil
        Prefs.history = history
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
    private var sidebar: NSSplitViewItem!
    private var settings: NSWindow?
    private var tabs: SettingsTabs?
    private var overlay: NSView?
    private var ws: Workspace!
    private var editor: EditorController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        Brand.register()
        let env = ProcessInfo.processInfo.environment
        let vault = URL(fileURLWithPath: env["QUILL_VAULT"] ?? Prefs.vault ?? NSHomeDirectory() + "/Quill")
        let fresh = !FileManager.default.fileExists(atPath: vault.path)
        ws = Workspace(vault: vault)
        ws.showSettings = { [weak self] in self?.show($0) }
        if fresh { seed(vault) }

        editor = EditorController(ws: ws)
        let split = NSSplitViewController()
        let side = NSSplitViewItem(sidebarWithViewController: NSHostingController(rootView: Sidebar(ws: ws, chrome: editor.chrome, settings: { [weak self] in self?.show($0) })))
        sidebar = side
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
        if !Prefs.onboarded || ProcessInfo.processInfo.arguments.contains("--onboarding") { onboard() }
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

        Here is a pitch with a weak opening. Hold the **\(Prefs.talkKey.label)** key, say *"make the first sentence confident and short"*, then let go.

        > We are basically trying to kind of build a tool that maybe helps people write better, in a way.

        Writers lose hours to editing. Quill gives them an editor that listens, then shows its work: every change lands in front of you, tinted until you keep it or revert it.

        ## Good to know

        - Press ⌘K to type a request instead of speaking, or ⇧⌘K to talk without holding a key.
        - Select a passage first and "this" means that passage.
        - Put the caret in a change to see what it replaced. ⌘↩ keeps it, ⌘⌫ reverts it, ⌘] jumps to the next one.
        - One ⌘Z takes back a whole request.
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
            item("Quick Open…", #selector(quickOpen), "p", target: self),
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
        let spelling = NSMenu(title: "Spelling and Grammar")
        [
            item("Show Spelling and Grammar", #selector(NSText.showGuessPanel(_:)), ":"),
            item("Check Document Now", #selector(NSText.checkSpelling(_:)), ";"),
            .separator(),
            item("Check Spelling While Typing", #selector(NSTextView.toggleContinuousSpellChecking(_:))),
        ].forEach(spelling.addItem)
        let spellingItem = item("Spelling and Grammar", nil)
        spellingItem.submenu = spelling
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
            spellingItem,
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
            item("Body Text", #selector(QuillTextView.heading(_:)), tag: 0),
        ])
        let agents = NSMenu(title: "Co-writer")
        for (i, spec) in AgentSpec.all.enumerated() {
            let row = item(spec.name, #selector(chooseAgent(_:)), target: self, tag: i)
            row.image = Mark.image(spec, dark: NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
            agents.addItem(row)
        }
        agents.addItem(.separator())
        agents.addItem(item("Co-writer Settings…", #selector(moreModels), target: self))
        let agentsItem = item("Co-writer", nil)
        agentsItem.submenu = agents
        let models = NSMenu(title: "Model")
        models.delegate = self
        let modelsItem = item("Model", nil)
        modelsItem.submenu = models
        let hold = item("Hold to Talk", #selector(holdHint), target: self)
        _ = add("Agent", [
            item("Ask…", #selector(ask), "k", target: self),
            item("Talk", #selector(toggleTalk), "k", [.command, .shift], target: self),
            hold,
            item("Stop", #selector(stop), ".", target: self),
            .separator(),
            item("Keep Change", #selector(keepChange), "\r", target: self),
            item("Revert Change", #selector(revertChange), "\u{8}", target: self),
            item("Keep All Changes", #selector(keepAll), "\r", [.command, .shift], target: self),
            item("Revert All Changes", #selector(revertAll), "\u{8}", [.command, .shift], target: self),
            item("Next Change", #selector(nextChange), "]", target: self),
            item("Previous Change", #selector(previousChange), "[", target: self),
            .separator(),
            item("Guided Edits", #selector(guided), "1", [.command, .control], target: self),
            item("Margin Notes", #selector(notesMode), "2", [.command, .control], target: self),
            .separator(),
            agentsItem,
            modelsItem,
        ])
        _ = add("View", [
            item("Hide Sidebar", #selector(NSSplitViewController.toggleSidebar(_:)), "s", [.command, .control]),
            .separator(),
            item("Actual Size", #selector(EditorController.actualSize(_:)), "0"),
            item("Zoom In", #selector(EditorController.zoomIn(_:)), "+"),
            {
                let i = item("Zoom In", #selector(EditorController.zoomIn(_:)), "=")
                i.isHidden = true
                i.allowsKeyEquivalentWhenHidden = true
                return i
            }(),
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
            item("Show Onboarding", #selector(onboard), target: self),
        ])
        return bar
    }

    @objc private func newNote() { ws.create() }
    @objc private func ask() { editor.command() }
    @objc private func toggleTalk() { editor.toggleTalk() }
    @objc private func holdHint() {}
    @objc private func stop() { ws.cancelTurn() }
    @objc private func keepChange() { ws.focused.map { ws.keep([$0]) } }
    @objc private func revertChange() { ws.focused.map { ws.revert([$0]) } }
    @objc private func keepAll() { ws.keep() }
    @objc private func revertAll() { ws.revert() }
    @objc private func nextChange() { ws.step(true) }
    @objc private func previousChange() { ws.step(false) }
    @objc private func chooseModel(_ sender: NSMenuItem) { (sender.representedObject as? String).map(ws.choose(model:)) }
    @objc private func quickOpen() {
        if sidebar.isCollapsed { sidebar.animator().isCollapsed = false }
        editor.chrome.searching = true
    }
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
            self.ws.fail(problem)
        }
    }

    @objc private func trash() {
        guard let note = ws.notes.first(where: { $0.url == ws.current }) else { return }
        ws.trash(note)
    }

    @objc func onboard() {
        guard let content = window.contentView, overlay == nil else { return }
        Prefs.onboardStarted = Date.now.timeIntervalSince1970
        Ledger.event("onboarding-started")
        let run = Firstrunner(current: ws.vault)
        let host = NSHostingView(rootView: Onboarding(ws: ws, run: run) { [weak self] picked in self?.landed(picked) })
        host.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            host.topAnchor.constraint(equalTo: content.topAnchor),
            host.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        overlay = host
    }

    private func landed(_ picked: (sentence: String, source: String)?) {
        let (sentence, source) = picked ?? ("We are basically trying to kind of build a tool that maybe helps people write better, in a way.", "a sample pitch")
        let practice = Ledger.dir.appending(path: "Practice")
        try? FileManager.default.createDirectory(at: practice, withIntermediateDirectories: true)
        let url = practice.appending(path: "Your first edit.md")
        try? "# Your first edit\n\nThis page lives outside your notes, so nothing here touches them.\n\n\(sentence)\n".write(to: url, atomically: true, encoding: .utf8)
        ws.open(url)
        let r = (editor.text.string as NSString).range(of: sentence)
        if r.location != NSNotFound { editor.text.setSelectedRange(r) }
        window.makeFirstResponder(editor.text)
        editor.chrome.hinting = false
        editor.chrome.coach = source
        Prefs.onboarded = true
        Ledger.event("onboarding-finished")
        guard let overlay else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.15 : 0.7
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.77, 0, 0.175, 1)
            overlay.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                overlay.removeFromSuperview()
                self?.overlay = nil
            }
        })
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

    @objc private func openSettings() { show(nil) }

    func show(_ pane: Pane?) {
        if settings == nil {
            let tabs = SettingsTabs.make(ws, editor.chrome)
            let w = NSWindow(contentViewController: tabs)
            w.styleMask = [.titled, .closable]
            w.toolbarStyle = .preference
            w.isReleasedWhenClosed = false
            w.setFrameAutosaveName("Settings")
            tabs.show(Prefs.pane.flatMap(Pane.init(rawValue:)) ?? .general)
            if !w.setFrameUsingName("Settings") { w.center() }
            settings = w
            self.tabs = tabs
        }
        if let pane { tabs?.show(pane) }
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
        case #selector(ask), #selector(toggleTalk), #selector(rename), #selector(trash), #selector(save):
            return ws.current != nil
        case #selector(holdHint):
            item.title = "Hold \(editor.chrome.talkKey.title) to Talk"
            return false
        case #selector(keepChange), #selector(revertChange):
            return ws.focused != nil
        case #selector(keepAll), #selector(revertAll), #selector(nextChange), #selector(previousChange):
            return !ws.review.isEmpty
        case #selector(chooseModel(_:)):
            item.state = ws.model?.id == item.representedObject as? String ? .on : .off
        default: break
        }
        return true
    }
}

extension AppDelegate: NSMenuItemValidation {}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard !ws.models.isEmpty else {
            let empty = NSMenuItem(title: "Starting \(ws.spec.name)…", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            return
        }
        for model in ws.recommended {
            let i = NSMenuItem(title: model.name, action: #selector(chooseModel(_:)), keyEquivalent: "")
            i.target = self
            i.representedObject = model.id
            i.state = model == ws.model ? .on : .off
            menu.addItem(i)
        }
        if ws.models.count > ws.recommended.count {
            menu.addItem(.separator())
            let more = NSMenuItem(title: "More Models…", action: #selector(moreModels), keyEquivalent: "")
            more.target = self
            menu.addItem(more)
        }
    }

    @objc private func moreModels() { show(.cowriters) }
}

extension EditorController: NSMenuItemValidation {
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(zoomIn(_:)): scroll.magnification < scroll.maxMagnification - 0.01
        case #selector(zoomOut(_:)): scroll.magnification > scroll.minMagnification + 0.01
        case #selector(actualSize(_:)): abs(scroll.magnification - 1) > 0.01
        default: true
        }
    }
}

@MainActor
final class EditorController: NSViewController {
    let ws: Workspace
    let chrome = Chrome()
    private(set) var text: QuillTextView!
    fileprivate var scroll: NSScrollView!
    private var cards: [Int: NSHostingView<NoteCard>] = [:]
    private var activeNote: Int?
    private var changeCard: NSHostingView<Gloss>?
    private var hovered: Int?
    private var overCard = false
    private var monitor: Any?
    private var holding = false
    private var toggled = false
    private var chord = false
    private var lastKey: CFAbsoluteTime = 0

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
        ws.attach(text, choreographer)
        let review = text.onReview
        text.onReview = { [weak self] in
            review?()
            self?.layoutCard()
        }
        text.onEdit = { [weak self] in
            self?.ws.edited()
            self?.layoutNotes()
        }
        text.onCaret = { [weak self] in self?.layoutCard() }
        text.onHover = { [weak self] index in
            guard let self else { return }
            let id = index.flatMap { self.ws.review.hunk(at: $0)?.id }
            if id != self.hovered { self.hovered = id; self.layoutCard() }
        }
        text.beforeKey = { [weak self, weak choreographer] event in
            guard let self else { return false }
            let now = CFAbsoluteTimeGetCurrent()
            defer { self.lastKey = now }
            guard let choreographer, choreographer.isBusy else { return false }
            choreographer.land()
            guard let event, event.keyCode == 49, event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty else { return false }
            return now - self.lastKey > 2
        }
        NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: text, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.layoutNotes()
                self?.layoutCard()
            }
        }
        scroll.allowsMagnification = true
        scroll.minMagnification = 0.7
        scroll.maxMagnification = 2
        if Prefs.zoom > 0 { scroll.magnification = Prefs.zoom }
        NotificationCenter.default.addObserver(forName: NSScrollView.didEndLiveMagnifyNotification, object: scroll, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if let self { Prefs.zoom = self.scroll.magnification } }
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
        Prefs.zoom = clamped
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        title()
    }

    private func observe() {
        withObservationTracking {
            _ = ws.margin
            _ = ws.phase
            _ = ws.current
            _ = ws.busy
            _ = chrome.commanding
            _ = chrome.searching
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.title()
                self.announce()
                if !self.chrome.commanding, !self.chrome.searching, self.view.window?.firstResponder !== self.text {
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

    private var spoken = ""
    private func announce() {
        let kind = "\(ws.phase)".prefix { $0 != "(" }
        let id = kind == "thinking" || kind == "applying" ? String(kind) : "\(ws.phase)"
        guard id != spoken else { return }
        spoken = id
        let line: String? = switch ws.phase {
        case .done(let n): n == 0 ? "Nothing to change" : n == 1 ? "1 change to review. Command Return keeps it." : "\(n) changes to review. Command Shift Return keeps them all."
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
            if chrome.coach != nil {
                chrome.coach = nil
                if Prefs.onboardStarted > 0 {
                    Ledger.event("first-edit", detail: String(format: "%.1f", Date.now.timeIntervalSince1970 - Prefs.onboardStarted))
                }
            }
            if chrome.hinting {
                chrome.hinting = false
                Prefs.spoke = true
            }
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

    func toggleTalk() {
        if toggled {
            toggled = false
            release()
        } else if !holding {
            toggled = true
            press()
        }
    }

    private func listen() {
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.holding, !self.toggled else { return }
                self.holding = false
                self.ws.listener.cancel()
                self.ws.phase = .idle
            }
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            guard let self, event.window == self.view.window else { return event }
            if event.type == .keyDown {
                if self.toggled, event.keyCode == 36 || event.keyCode == 76 {
                    self.toggleTalk()
                    return nil
                }
                if self.holding, !self.toggled { self.chord = true; self.ws.cancelTurn(); self.holding = false }
                if event.keyCode == 53 {
                    if self.toggled { self.toggled = false; self.holding = false; self.ws.cancelTurn(); return nil }
                    if self.chrome.commanding { self.chrome.commanding = false; return nil }
                    switch self.ws.phase {
                    case .idle: break
                    case .thinking, .applying: self.ws.cancelTurn(); return nil
                    default: self.ws.phase = .idle; return nil
                    }
                }
                return event
            }
            let key = self.chrome.talkKey
            guard event.keyCode == key.keyCode, !self.toggled else { return event }
            let raw = event.modifierFlags.rawValue
            let down: Bool = switch key {
            case .rightOption: raw & 0x40 != 0 && event.modifierFlags.intersection([.command, .control, .shift]).isEmpty
            case .rightCommand: raw & 0x10 != 0 && event.modifierFlags.intersection([.option, .control, .shift]).isEmpty
            case .fn: event.modifierFlags.contains(.function) && event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
            }
            if down, !self.holding { self.press() } else if !down, self.holding { self.release() }
            return event
        }
    }

    private func press() {
        guard !ws.busy else { toggled = false; return }
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
                toggled = false
                return
            }
            guard holding else { return }
            ws.phase = .listening("")
            do { try await ws.listener.start() } catch {
                ws.fail("Couldn't start listening: \(error.localizedDescription)")
                holding = false
                toggled = false
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

    private func layoutCard() {
        let id = overCard ? changeCard?.rootView.hunk.id : hovered ?? ws.focused?.id
        text.focused = id
        if ws.focusID != id { ws.focusID = id }
        guard let id, let hunk = ws.review.hunk(id), let bar = text.bar(hunk) else {
            changeCard?.removeFromSuperview()
            changeCard = nil
            overCard = false
            return
        }
        let right = text.textContainerOrigin.x + (text.textContainer?.size.width ?? Theme.column) + 24
        let room = text.bounds.width - right - 20
        let width: CGFloat? = room >= 150 ? min(220, room) : nil
        let boxed = width == nil
        let gloss = Gloss(
            hunk: hunk,
            width: width,
            keep: { [weak self] in
                self?.overCard = false
                self?.ws.keep([hunk])
            },
            revert: { [weak self] in
                self?.overCard = false
                self?.ws.revert([hunk])
            },
            hover: { [weak self] on in
                self?.overCard = on
                if !on { self?.layoutCard() }
            }
        )
        if changeCard?.rootView.hunk.id != id || changeCard?.rootView.width != width {
            changeCard?.removeFromSuperview()
            let h = NSHostingView(rootView: gloss)
            h.sizingOptions = [.intrinsicContentSize]
            text.addSubview(h)
            changeCard = h
        }
        guard let host = changeCard else { return }
        host.rootView = gloss
        let size = host.fittingSize
        if boxed {
            let x = min(max(text.textContainerOrigin.x + Theme.hang, bar.minX + 20), text.bounds.width - size.width - 12)
            host.frame = CGRect(x: x, y: bar.maxY + 8, width: size.width, height: size.height)
        } else {
            host.frame = CGRect(x: right, y: bar.minY - 2, width: size.width, height: size.height)
        }
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
            if activeNote == note.id { look[.backgroundColor] = Theme.accent.withAlphaComponent(0.12) }
            text.mark(note.range, look)
            let card = cards[note.id] ?? {
                let h = NSHostingView(rootView: NoteCard(note: note, active: false, busy: false, apply: {}, dismiss: {}, hover: { _ in }))
                h.sizingOptions = [.intrinsicContentSize]
                text.addSubview(h)
                cards[note.id] = h
                return h
            }()
            card.rootView = NoteCard(
                note: note,
                active: activeNote == note.id,
                busy: ws.busy,
                apply: { [weak self] in self?.apply(note) },
                dismiss: { [weak self] in
                    Ledger.event("note-dismissed", detail: "\(note.lens ?? "-"): \(note.note)")
                    self?.ws.margin.removeAll { $0.id == note.id }
                },
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
        guard !ws.busy else { return }
        Ledger.event("note-applied", detail: "\(note.lens ?? "-"): \(note.note)")
        ws.margin.removeAll { $0.id == note.id }
        ws.ask("Apply your note about \"\(note.quote)\": \(note.note)", mode: .guided)
    }
}

func stamp(_ date: Date, now: Date = .now) -> String {
    let cal = Calendar.current
    if cal.isDateInToday(date) { return date.formatted(date: .omitted, time: .shortened) }
    if cal.isDateInYesterday(date) { return "Yesterday" }
    if let days = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: now)).day, days < 7 {
        return date.formatted(.dateTime.weekday(.wide))
    }
    if cal.component(.year, from: date) == cal.component(.year, from: now) { return date.formatted(.dateTime.day().month(.abbreviated)) }
    return date.formatted(.dateTime.day().month(.abbreviated).year())
}

struct Sidebar: View {
    @Bindable var ws: Workspace
    @Bindable var chrome: Chrome
    var settings: (Pane?) -> Void = { _ in }
    @State private var renaming: Note?
    @State private var name = ""
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var shown: [Note] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return ws.notes }
        let lower = q.lowercased()
        return ws.notes.filter { $0.title.localizedStandardContains(q) }.sorted { a, b in
            let pa = a.title.lowercased().hasPrefix(lower), pb = b.title.lowercased().hasPrefix(lower)
            return pa != pb ? pa : a.modified > b.modified
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Color.soft)
                TextField("Search notes", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .focused($searchFocused)
                    .onSubmit {
                        if let first = shown.first { ws.open(first.url) }
                        query = ""
                        chrome.searching = false
                    }
                    .onExitCommand {
                        query = ""
                        chrome.searching = false
                    }
                if query.isEmpty {
                    Keycap("⌘P")
                } else {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 11)) }
                        .buttonStyle(.plain).foregroundStyle(Color.soft)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.ink.opacity(0.05)))
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 4)
            List(selection: Binding(get: { ws.current }, set: { if let url = $0 { ws.open(url) } })) {
                Section {
                    ForEach(shown) { note in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(note.title).font(.serif(15.5, .medium)).lineLimit(1)
                            TimelineView(.everyMinute) { _ in
                                Text(stamp(note.modified))
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
                        Text(ws.title)
                        Spacer()
                        Button { ws.create() } label: { Image(systemName: "square.and.pencil") }
                            .buttonStyle(.plain).help("New note (⌘N)")
                    }
                }
            }
            .listStyle(.sidebar)
            .overlay {
                if shown.isEmpty, !query.isEmpty {
                    Text("No notes match “\(query)”").font(.system(size: 12)).foregroundStyle(Color.soft)
                }
            }
            AgentBadge(ws: ws, settings: settings)
        }
        .onChange(of: chrome.searching) { _, on in searchFocused = on }
        .onChange(of: searchFocused) { _, on in if !on { chrome.searching = false } }
        .alert("Rename note", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $name)
            Button("Rename") {
                if let r = renaming, let problem = ws.rename(r, to: name) { ws.fail(problem) }
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
                    .font(.serif(24, .medium)).foregroundStyle(Color.ink)
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
    var settings: (Pane?) -> Void
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
        case false?: return (.redInk, ws.spec.missing)
        case nil: return (.faint, nil)
        }
    }

    private var detail: String {
        [ws.model?.name, ws.mode == .notes ? "Notes" : nil].compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        let (dot, note) = state
        Menu {
            if ws.models.isEmpty {
                Text(ws.busy ? "Connecting…" : "Models load when \(ws.spec.name) connects")
            } else {
                Picker("Model", selection: Binding(get: { ws.model?.id ?? "" }, set: { ws.choose(model: $0) })) {
                    ForEach(ws.recommended) { m in Text(m.name).tag(m.id) }
                }
                .pickerStyle(.inline)
                if ws.models.count > ws.recommended.count {
                    Button("More Models…") { settings(.cowriters) }
                }
            }
            Divider()
            Picker("Answer with", selection: $ws.mode) {
                Text("Guided Edits").tag(Mode.guided)
                Text("Margin Notes").tag(Mode.notes)
            }
            .pickerStyle(.inline)
            Divider()
            Menu("Co-writer") {
                Picker("Co-writer", selection: $ws.agentID) {
                    ForEach(AgentSpec.all) { spec in
                        Label {
                            Text(spec.name)
                        } icon: {
                            if let image = Mark.image(spec, dark: false) { Image(nsImage: image) }
                        }
                        .tag(spec.id)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            Button("Settings…") { settings(nil) }
        } label: {
            HStack(spacing: 9) {
                Mark(spec: ws.spec, size: 16)
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color(nsColor: Theme.paper)))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color(nsColor: Theme.rule), lineWidth: 0.5))
                    .overlay(alignment: .bottomTrailing) {
                        Circle().fill(dot).frame(width: 7, height: 7)
                            .overlay(Circle().strokeBorder(Color(nsColor: Theme.sheet), lineWidth: 1.5))
                            .offset(x: 2, y: 2)
                    }
                VStack(alignment: .leading, spacing: 1) {
                    Text(ws.spec.name).font(.system(size: 12, weight: .medium)).foregroundStyle(Color.ink)
                    Text(note ?? detail)
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
        .help("Co-writer, model, and how it answers")
        .accessibilityLabel("\(ws.spec.name), \(note ?? detail)")
    }
}
