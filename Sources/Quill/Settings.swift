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
        Group {
            switch pane {
            case .general: GeneralPane(ws: ws)
            case .cowriters: CowritersPane(ws: ws)
            case .voice: VoicePane(ws: ws)
            case .shortcuts: ShortcutsPane(chrome: chrome)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct Footnote: View {
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

struct GeneralPane: View {
    @Bindable var ws: Workspace

    var body: some View {
        Form {
            Section {
                LabeledContent("Notes folder") {
                    HStack(spacing: 8) {
                        Text(ws.vault.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            .lineLimit(1).truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button("Change…") {
                            let panel = NSOpenPanel()
                            panel.canChooseDirectories = true
                            panel.canChooseFiles = false
                            panel.canCreateDirectories = true
                            panel.prompt = "Open"
                            panel.directoryURL = ws.vault
                            if panel.runModal() == .OK, let url = panel.url { ws.switchVault(url) }
                        }
                    }
                }
            } footer: {
                Footnote("Quill reads and writes plain Markdown files in this folder. Co-writers never touch it directly.")
            }
            Section {
                Picker("Answer with", selection: $ws.mode) {
                    Text("Guided edits").tag(Mode.guided)
                    Text("Margin notes").tag(Mode.notes)
                }
                .pickerStyle(.radioGroup)
            } footer: {
                Footnote(ws.mode == .guided
                    ? "Changes land in the text, underlined until you keep or revert them. One ⌘Z takes back a whole request."
                    : "The co-writer leaves notes in the margin. Apply a note to make its edit.")
            }
        }
    }
}

struct CowritersPane: View {
    @Bindable var ws: Workspace
    @State private var key = Keychain.read("anthropic") ?? ""

    private func saveKey() {
        let clean = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean != (Keychain.read("anthropic") ?? "") else { return }
        Keychain.write("anthropic", clean)
        ws.hasKey = Keychain.anthropicKey?.isEmpty == false
    }

    var body: some View {
        Form {
            Section {
                ForEach(AgentSpec.all) { spec in row(spec) }
            }
            Section {
                if ws.models.isEmpty {
                    LabeledContent("Model") {
                        Text(ws.busy ? "Connecting…" : "Loads when \(ws.spec.name) connects").foregroundStyle(.secondary)
                    }
                } else {
                    Picker("Model", selection: Binding(get: { ws.model?.id ?? "" }, set: { ws.choose(model: $0) })) {
                        ForEach(ws.models) { m in Text(m.name).tag(m.id) }
                    }
                }
            } footer: {
                Footnote("Every model \(ws.spec.name) offers. The co-writer menu shows the three most useful.")
            }
            Section {
                SecureField("API key", text: $key, prompt: Text("sk-ant-…"))
                    .onSubmit(saveKey)
                    .onChange(of: key) {
                        Task {
                            try? await Task.sleep(for: .milliseconds(600))
                            saveKey()
                        }
                    }
            } header: {
                Text("Anthropic API")
            } footer: {
                Footnote("Stored in your Keychain and sent only to Anthropic.")
            }
        }
        .onAppear { ws.checkAgents() }
        .onDisappear(perform: saveKey)
    }

    private func row(_ spec: AgentSpec) -> some View {
        let available = ws.available(spec)
        let chosen = ws.agentID == spec.id
        return HStack(alignment: .top, spacing: 12) {
            Mark(spec: spec, size: 22)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color(nsColor: Theme.sheet)))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color(nsColor: Theme.rule), lineWidth: 0.5))
                .saturation(available == false ? 0 : 1)
                .opacity(available == false ? 0.6 : 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(spec.name).font(.system(size: 13, weight: .medium))
                Text(spec.detail).font(.system(size: 11.5)).foregroundStyle(.secondary)
                if available == false, let install = spec.install {
                    Text(install)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 8)
            Group {
                switch available {
                case true?:
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.accentInk)
                        .opacity(chosen ? 1 : 0)
                case false?: Text(spec.missing).font(.system(size: 11.5)).foregroundStyle(.secondary)
                case nil: ProgressView().controlSize(.mini)
                }
            }
            .padding(.top, 7)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture { ws.agentID = spec.id }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
        .accessibilityValue(available == false ? spec.missing : "")
    }
}

struct VoicePane: View {
    @Bindable var ws: Workspace
    @State private var measuring = false

    private var learning: String {
        let turns = Ledger.read(TurnRecord.self, from: Ledger.turns)
        let edits = turns.flatMap(\.exchanges).filter { $0.outcome != .unreviewed }
        guard !edits.isEmpty else { return "Quill learns from every change you keep, revert, or rewrite. All of it stays on this Mac." }
        let kept = edits.filter { $0.outcome == .kept }.count
        return "Learned from \(edits.count) reviewed changes across \(turns.count) requests. You kept \(kept * 100 / edits.count)%. All of it stays on this Mac."
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
        Form {
            Section {
                ForEach(sources, id: \.self) { folder in
                    HStack {
                        Image(systemName: "folder").foregroundStyle(.secondary)
                        Text(folder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        if folder == ws.vault {
                            Text("Notes folder").font(.system(size: 11.5)).foregroundStyle(.secondary)
                        } else {
                            Button("Remove") { setSources(sources.filter { $0 != folder }) }.buttonStyle(.link)
                        }
                    }
                }
                Button("Add Folder…") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    if panel.runModal() == .OK, let url = panel.url { setSources(sources + [url]) }
                }
            } header: {
                Text("Learn from")
            } footer: {
                Footnote("Quill reads these folders to learn how you write. It never changes them.")
            }
            Section {
                LabeledContent("Your voice") {
                    HStack(spacing: 8) {
                        Button(measuring ? "Measuring…" : "Measure Again", action: measure).disabled(measuring)
                        Button("Open Voice.md") { ws.refresh(); ws.open(ws.keeper.url) }
                    }
                }
            } footer: {
                Footnote(learning)
            }
        }
    }
}

struct ShortcutsPane: View {
    @Bindable var chrome: Chrome

    private static let groups: [(String, [(String, String)])] = [
        ("Asking", [("Ask", "⌘K"), ("Talk", "⇧⌘K"), ("Stop", "⌘.")]),
        ("Reviewing", [
            ("Keep change", "⌘↩"), ("Revert change", "⌘⌫"),
            ("Keep all", "⇧⌘↩"), ("Revert all", "⇧⌘⌫"),
            ("Next change", "⌘]"), ("Previous change", "⌘["),
            ("Take back a request", "⌘Z"),
        ]),
        ("Notes", [("Find a note", "⌘P"), ("New note", "⌘N")]),
    ]

    var body: some View {
        Form {
            Section {
                Picker("Hold to talk", selection: $chrome.talkKey) {
                    ForEach(TalkKey.allCases) { k in Text(k.title).tag(k) }
                }
            } footer: {
                Footnote("Hold the key, speak, and let go to send.")
            }
            ForEach(Self.groups, id: \.0) { group in
                Section(group.0) {
                    ForEach(group.1, id: \.0) { name, keys in
                        LabeledContent(name) {
                            Text(keys).font(.system(size: 12.5, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
                        }
                    }
                }
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
        let name = spec.mark + (dark && spec.mark == "opencode" ? "-dark" : "")
        let key = "\(name)@\(size)"
        if let hit = cache[key] { return hit }
        guard let url = Brand.url("mark-\(name).svg"), let image = NSImage(contentsOf: url) else { return nil }
        image.size = NSSize(width: size, height: size)
        image.isTemplate = spec.mark == "codex"
        cache[key] = image
        return image
    }
}
