import AppKit
import SwiftUI
import QuillCore

enum Pane: String, CaseIterable {
    case general, cowriters, voice, shortcuts

    var title: String {
        switch self {
        case .general: "General"
        case .cowriters: "Co-writers"
        case .voice: "Voice"
        case .shortcuts: "Shortcuts"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .cowriters: "person.2"
        case .voice: "text.quote"
        case .shortcuts: "command"
        }
    }
}

final class SettingsTabs: NSTabViewController {
    override func tabView(_ tabView: NSTabView, didSelect item: NSTabViewItem?) {
        super.tabView(tabView, didSelect: item)
        if let id = item?.identifier as? String { Prefs.pane = id }
    }

    static func make(_ ws: Workspace, _ chrome: Chrome) -> SettingsTabs {
        let tabs = SettingsTabs()
        tabs.tabStyle = .toolbar
        tabs.transitionOptions = [.crossfade, .allowUserInteraction]
        for pane in Pane.allCases {
            let host = NSHostingController(rootView: PaneView(pane: pane, ws: ws, chrome: chrome))
            host.sizingOptions = .preferredContentSize
            host.title = pane.title
            let item = NSTabViewItem(viewController: host)
            item.label = pane.title
            item.identifier = pane.rawValue
            item.image = NSImage(systemSymbolName: pane.symbol, accessibilityDescription: pane.title)
            tabs.addTabViewItem(item)
        }
        return tabs
    }

    func show(_ pane: Pane) {
        selectedTabViewItemIndex = Pane.allCases.firstIndex(of: pane) ?? 0
    }
}

struct PaneView: View {
    var pane: Pane
    @Bindable var ws: Workspace
    @Bindable var chrome: Chrome

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            switch pane {
            case .general: GeneralPane(ws: ws)
            case .cowriters: CowritersPane(ws: ws)
            case .voice: VoicePane(ws: ws)
            case .shortcuts: ShortcutsPane(chrome: chrome)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 22)
        .padding(.bottom, 28)
        .frame(width: 580, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(nsColor: Theme.paper))
        .tint(Color.accentInk)
    }
}

extension Color {
    @MainActor static let sheet = Color(nsColor: Theme.sheet)
    @MainActor static let rule = Color(nsColor: Theme.rule)
}

struct Block<Content: View>: View {
    var title: String
    var note: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.ink)
            content
            if let note {
                Text(note).font(.system(size: 12)).foregroundStyle(Color.soft).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct Card<Content: View>: View {
    var padding: CGFloat = 0
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.sheet))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.rule, lineWidth: 1))
    }
}

struct Row<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            leading
            Spacer(minLength: 12)
            trailing
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
    }
}

struct Hairline: View {
    var body: some View { Rectangle().fill(Color.rule).frame(height: 1).padding(.leading, 14) }
}

struct GeneralPane: View {
    @Bindable var ws: Workspace

    var body: some View {
        Block(title: "Notes folder", note: "Quill keeps plain Markdown files here. Co-writers only ever edit a copy.") {
            Card {
                Row {
                    Image(systemName: "folder.fill").font(.system(size: 18)).foregroundStyle(Color.accentInk)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(ws.vault.lastPathComponent).font(.system(size: 13, weight: .medium)).foregroundStyle(Color.ink).lineLimit(1).truncationMode(.middle)
                        Text(ws.vault.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            .font(.system(size: 11.5)).foregroundStyle(Color.soft).lineLimit(1).truncationMode(.middle)
                    }
                } trailing: {
                    Button("Change…") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        panel.canCreateDirectories = true
                        panel.prompt = "Open"
                        panel.directoryURL = ws.vault
                        if panel.runModal() == .OK, let url = panel.url { ws.switchVault(url) }
                    }
                    .controlSize(.regular)
                }
                .padding(.vertical, 6)
            }
        }
        Block(title: "When you ask") {
            HStack(spacing: 12) {
                Choice(on: ws.mode == .guided, title: "Guided edits", detail: "Changes land in the text. You keep or revert each one.") {
                    GuidedSample()
                } pick: { ws.mode = .guided }
                Choice(on: ws.mode == .notes, title: "Margin notes", detail: "Notes beside the text. You apply the ones you like.") {
                    NotesSample()
                } pick: { ws.mode = .notes }
            }
        }
    }
}

struct Choice<Sample: View>: View {
    var on: Bool
    var title: String
    var detail: String
    @ViewBuilder var sample: Sample
    var pick: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: pick) {
            VStack(alignment: .leading, spacing: 0) {
                sample
                    .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
                    .padding(.horizontal, 16)
                    .background(Color(nsColor: Theme.paper))
                Rectangle().fill(Color.rule).frame(height: 1)
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.ink)
                        Spacer()
                        Image(systemName: on ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 14))
                            .foregroundStyle(on ? Color.accentInk : Color.faint)
                    }
                    Text(detail).font(.system(size: 11.5)).foregroundStyle(Color.soft).fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
            }
            .background(Color.sheet)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(on ? Color.accentInk : Color.rule.opacity(hovering ? 2 : 1), lineWidth: on ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(Press())
        .onHover { hovering = $0 }
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }
}

struct GuidedSample: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Capsule().fill(Color.accentInk.opacity(0.6)).frame(width: 2, height: 18).padding(.top, 3)
            (Text("We ") + Text("build").underline(true, color: Color.accentInk.opacity(0.6)) + Text(" a tool that helps people write."))
                .font(.serif(15)).foregroundStyle(Color.ink).lineSpacing(2)
        }
    }
}

struct NotesSample: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            (Text("We are ") + Text("basically").underline(true, color: Color.accentInk.opacity(0.5)) + Text(" building a tool."))
                .font(.serif(15)).foregroundStyle(Color.ink).lineSpacing(2)
            HStack(alignment: .top, spacing: 6) {
                Rectangle().fill(Color.accentInk).frame(width: 1.5, height: 32)
                Text("Cut the hedge.").font(.serif(13).italic()).foregroundStyle(Color.soft).fixedSize()
            }
        }
    }
}

struct CowritersPane: View {
    @Bindable var ws: Workspace
    @State private var key = ""

    private func saveKey() {
        let id = ws.agentID
        guard !ws.spec.keys.isEmpty else { return }
        let clean = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean != (Keychain.read(id) ?? "") else { return }
        Keychain.write(id, clean)
        if Keychain.key(for: id) != nil { ws.keyed.insert(id) } else { ws.keyed.remove(id) }
    }

    private func grid(_ specs: [AgentSpec]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(specs) { spec in
                Tile(spec: spec, on: ws.agentID == spec.id, available: ws.available(spec)) { ws.agentID = spec.id }
            }
        }
    }

    var body: some View {
        Block(title: "Agents", note: "Quill signs in through the tool you pick, so your existing plan works.") {
            grid(AgentSpec.all.filter { !$0.api })
        }
        Block(title: "API keys", note: "Pay per use with your own key. Keys stay in your Keychain.") {
            grid(AgentSpec.all.filter(\.api))
        }
        Block(title: ws.spec.name, note: hint) {
            Card {
                Row {
                    Text("Model").font(.system(size: 13)).foregroundStyle(Color.ink)
                } trailing: {
                    if ws.models.isEmpty {
                        Text(ws.busy ? "Connecting…" : "Loads when \(ws.spec.name) connects").font(.system(size: 12.5)).foregroundStyle(Color.soft)
                    } else {
                        Picker("", selection: Binding(get: { ws.model?.id ?? "" }, set: { ws.choose(model: $0) })) {
                            ForEach(ws.models) { m in Text(m.name).tag(m.id) }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }
                if !ws.spec.keys.isEmpty {
                    Hairline()
                    Row {
                        Text("API key").font(.system(size: 13)).foregroundStyle(Color.ink)
                    } trailing: {
                        SecureField("", text: $key, prompt: Text(ws.keyed.contains(ws.agentID) && key.isEmpty ? "From \(ws.spec.keys[0])" : "Paste your key"))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 240)
                            .onSubmit(saveKey)
                            .onChange(of: key) {
                                Task {
                                    try? await Task.sleep(for: .milliseconds(600))
                                    saveKey()
                                }
                            }
                    }
                }
            }
        }
        .onAppear {
            key = Keychain.read(ws.agentID) ?? ""
            ws.checkAgents()
        }
        .onChange(of: ws.agentID) { key = Keychain.read(ws.agentID) ?? "" }
        .onDisappear(perform: saveKey)
    }

    private var hint: String? {
        if !ws.spec.keys.isEmpty { return "Your key is stored in the Keychain and sent only to \(ws.spec.name)." }
        guard let install = ws.spec.install else { return nil }
        return ws.available(ws.spec) == false || install.hasPrefix("Downloads") ? install : nil
    }
}

struct Tile: View {
    var spec: AgentSpec
    var on: Bool
    var available: Bool?
    var pick: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: pick) {
            HStack(spacing: 10) {
                Mark(spec: spec, size: 18)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color(nsColor: Theme.paper)))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.rule, lineWidth: 1))
                VStack(alignment: .leading, spacing: 1) {
                    Text(spec.name).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Color.ink).lineLimit(1)
                    Text(status).font(.system(size: 11)).foregroundStyle(available == false ? Color.soft : Color.soft.opacity(0.9)).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(9)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(on ? Color.accentInk.opacity(0.08) : Color.sheet.opacity(hovering ? 1 : 0.7)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(on ? Color.accentInk : Color.rule, lineWidth: on ? 1.5 : 1))
            .opacity(available == false && !on ? 0.6 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(Press())
        .onHover { hovering = $0 }
        .help(spec.detail)
        .accessibilityLabel("\(spec.name), \(status)")
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    private var status: String {
        switch available {
        case false?: spec.missing
        case nil: "Checking…"
        case true?: on ? "In use" : spec.detail
        }
    }
}

struct VoicePane: View {
    @Bindable var ws: Workspace
    @State private var measuring = false

    private var learning: String {
        let turns = Ledger.read(TurnRecord.self, from: Ledger.turns)
        let edits = turns.flatMap(\.exchanges).filter { $0.outcome != .unreviewed }
        guard !edits.isEmpty else { return "Quill learns from every change you keep, revert, or rewrite. It all stays on this Mac." }
        let kept = edits.filter { $0.outcome == .kept }.count
        return "Learned from \(edits.count) reviewed changes across \(turns.count) requests. You kept \(kept * 100 / edits.count)%. It all stays on this Mac."
    }

    private func setSources(_ urls: [URL]) {
        Prefs.voiceSources = urls.filter { $0 != ws.vault }.map(\.path)
        measure()
    }

    private func measure() {
        measuring = true
        Task { await ws.measure(); measuring = false }
    }

    var body: some View {
        let sources = ws.voiceSources
        Block(title: "Learn from", note: "Quill reads these folders to learn how you write. It never changes them.") {
            Card {
                ForEach(Array(sources.enumerated()), id: \.element) { i, folder in
                    if i > 0 { Hairline() }
                    Row {
                        Image(systemName: "folder").foregroundStyle(Color.soft)
                        Text(folder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            .font(.system(size: 13)).foregroundStyle(Color.ink).lineLimit(1).truncationMode(.middle)
                    } trailing: {
                        if folder == ws.vault {
                            Text("Notes folder").font(.system(size: 11.5)).foregroundStyle(Color.soft)
                        } else {
                            Button("Remove") { setSources(sources.filter { $0 != folder }) }.buttonStyle(.link)
                        }
                    }
                }
                Hairline()
                Row {
                    Button {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        if panel.runModal() == .OK, let url = panel.url { setSources(sources + [url]) }
                    } label: {
                        Label("Add Folder…", systemImage: "plus").font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentInk)
                } trailing: { EmptyView() }
            }
        }
        Block(title: "Your voice", note: learning) {
            Card {
                Row {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Voice.md").font(.system(size: 13, weight: .medium)).foregroundStyle(Color.ink)
                        Text("Your rules, and what Quill has learned").font(.system(size: 11.5)).foregroundStyle(Color.soft)
                    }
                } trailing: {
                    HStack(spacing: 8) {
                        Button(measuring ? "Measuring…" : "Measure Again", action: measure).disabled(measuring)
                        Button("Open") { ws.refresh(); ws.open(ws.keeper.url) }
                    }
                }
                .padding(.vertical, 4)
                Hairline()
                Row {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Writing guide").font(.system(size: 13, weight: .medium)).foregroundStyle(Color.ink)
                        Text(Guide.skill.map { "Quill's guide plus your prose skill, \($0.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))" } ?? "Quill's editorial guide")
                            .font(.system(size: 11.5)).foregroundStyle(Color.soft).lineLimit(1).truncationMode(.middle)
                    }
                } trailing: {
                    if let skill = Guide.skill {
                        Button("Open") { NSWorkspace.shared.open(skill.appending(path: "SKILL.md")) }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

struct ShortcutsPane: View {
    @Bindable var chrome: Chrome

    private static let groups: [(String, [(String, String)])] = [
        ("Asking", [("Ask", "⌘K"), ("Talk without holding", "⇧⌘K"), ("Stop", "⌘.")]),
        ("Reviewing", [
            ("Keep change", "⌘↩"), ("Revert change", "⌘⌫"),
            ("Keep all", "⇧⌘↩"), ("Revert all", "⇧⌘⌫"),
            ("Next change", "⌘]"), ("Previous change", "⌘["),
            ("Take back a request", "⌘Z"),
        ]),
        ("Notes", [("Find a note", "⌘P"), ("New note", "⌘N"), ("Settings", "⌘,")]),
    ]

    var body: some View {
        Block(title: "Hold to talk", note: "Hold the key, speak, and let go to send.") {
            Picker("", selection: $chrome.talkKey) {
                ForEach(TalkKey.allCases) { k in Text(k.title).tag(k) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 22) {
                list(Self.groups[0])
                list(Self.groups[2])
            }
            list(Self.groups[1])
        }
    }

    private func list(_ group: (String, [(String, String)])) -> some View {
        Block(title: group.0) {
            Card {
                ForEach(Array(group.1.enumerated()), id: \.offset) { i, item in
                    if i > 0 { Hairline() }
                    HStack {
                        Text(item.0).font(.system(size: 12.5)).foregroundStyle(Color.ink)
                        Spacer(minLength: 8)
                        Keys(item.1)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                }
            }
        }
    }
}

struct Keys: View {
    var keys: String
    init(_ keys: String) { self.keys = keys }
    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, k in
                Text(String(k))
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.ink)
                    .frame(minWidth: 18, minHeight: 18)
                    .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color(nsColor: Theme.paper)))
                    .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Color.rule, lineWidth: 1))
            }
        }
    }
}

struct Mark: View {
    var spec: AgentSpec
    var size: CGFloat = 16
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let image = Self.image(spec, dark: scheme == .dark) {
            Image(nsImage: image)
                .resizable()
                .renderingMode(image.isTemplate ? .template : .original)
                .interpolation(.high)
                .scaledToFit()
                .foregroundStyle(Color.ink)
                .frame(width: size, height: size)
        }
    }

    @MainActor private static var cache: [String: NSImage] = [:]

    @MainActor static func image(_ spec: AgentSpec, dark: Bool, size: CGFloat = 16) -> NSImage? {
        let key = "\(spec.mark)\(dark)@\(size)"
        if let hit = cache[key] { return hit }
        let names = (dark ? ["mark-\(spec.mark)-dark.svg"] : []) + ["mark-\(spec.mark).svg", "mark-\(spec.mark).png"]
        guard let url = names.lazy.compactMap(Brand.url).first, let image = NSImage(contentsOf: url) else { return nil }
        let natural = image.size
        let side = max(natural.width, natural.height, 1)
        image.size = NSSize(width: size * natural.width / side, height: size * natural.height / side)
        image.isTemplate = ["codex", "gemini", "devin", "openrouter", "groq", "ollama"].contains(spec.mark)
        cache[key] = image
        return image
    }
}
