import SwiftUI
import QuillCore

extension Color {
    @MainActor static let ink = Color(nsColor: Theme.ink)
    @MainActor static let soft = Color(nsColor: Theme.soft)
    @MainActor static let faint = Color(nsColor: Theme.faint)
    @MainActor static let accentInk = Color(nsColor: Theme.accent)
    @MainActor static let redInk = Color(nsColor: Theme.red)
    @MainActor static let greenInk = Color(nsColor: Theme.green)
}

extension Font {
    static func voice(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        Brand.display(size - 2, weight)
    }
}

let enter = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.24)
let morph = Animation.spring(duration: 0.38, bounce: 0.12)

struct Pill: View {
    @Bindable var ws: Workspace
    @Bindable var chrome: Chrome
    @State private var hovering = false
    @State private var pick = 0
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let key = shown {
                surface
                    .id("pill")
                    .animation(reduceMotion ? nil : morph, value: key)
                    .transition(.asymmetric(insertion: .scale(scale: 0.94, anchor: .bottom).combined(with: .opacity),
                                            removal: .opacity.animation(.easeOut(duration: 0.14))))
            }
        }
        .animation(reduceMotion ? nil : enter, value: shown == nil)
        .padding(.bottom, 26)
        .frame(maxWidth: .infinity, alignment: .bottom)
    }

    private var pending: Int { ws.review.hunks.count }

    private var shown: String? {
        if chrome.commanding { return "command" }
        if chrome.coach != nil, ws.phase == .idle { return "coach" }
        switch ws.phase {
        case .idle: return pending > 0 ? "review\(pending)" : chrome.hinting ? "hint" : nil
        case .listening: return "listening"
        case .thinking(let a, _): return "thinking" + a
        case .applying(let n): return "applying\(n)"
        case .said(let s): return "said" + s + "\(pending)"
        case .done(let n): return "done\(n)\(pending)"
        case .failed(let s): return "failed" + s
        }
    }

    private var surface: some View {
        content
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(minHeight: 44)
            .glassEffect(.regular, in: .rect(cornerRadius: 22))
            .onHover { hovering = $0 }
    }

    @ViewBuilder
    private var content: some View {
        if chrome.commanding {
            command
        } else if let source = chrome.coach, ws.phase == .idle {
            coach(source)
        } else {
            switch ws.phase {
            case .idle:
                if pending > 0 { reviewRow } else { hint }
            case .listening(let text):
                listening(text)
            case .thinking(let activity, let words):
                thinking(activity, words)
            case .applying(let n):
                thinking(n == 1 ? "Writing 1 change" : "Writing \(n) changes", nil)
            case .said(let text):
                said(text)
            case .done(let n):
                if pending > 0 { reviewRow } else { done(n).task(id: shown) { await dismiss(after: 2.4) } }
            case .failed(let message):
                failed(message)
            }
        }
    }

    private func coach(_ source: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Try it on \(source). Hold \(Prefs.talkKey.label) and say what you'd change, like “make it direct”.")
                .font(.voice(18)).foregroundStyle(Color.ink).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button {
                    ws.ask("Make this sentence say what I mean, in my voice.", mode: .guided)
                } label: {
                    HStack(spacing: 8) {
                        Text("Make it say what I mean").font(.voice(17, .medium))
                        Text("⌘↩").font(.system(size: 11, weight: .medium)).opacity(0.7)
                    }
                    .foregroundStyle(Color(nsColor: Theme.onAccent))
                    .padding(.horizontal, 16)
                    .frame(height: 34)
                    .background(Capsule().fill(Color.accentInk))
                }
                .buttonStyle(Press())
                .keyboardShortcut(.return, modifiers: .command)
                Text("or press ⌘K to type").font(.system(size: 12)).foregroundStyle(Color.soft)
            }
        }
        .padding(.vertical, 4)
        .frame(width: 400, alignment: .leading)
    }

    private var hint: some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) { Keycap(Prefs.talkKey.label); Text("hold to talk") }
            HStack(spacing: 6) { Keycap("⌘K"); Text("type") }
        }
        .font(.system(size: 12))
        .foregroundStyle(Color.soft)
    }

    private var index: Int? {
        ws.review.hunks.firstIndex { $0.id == ws.focusID }
    }

    private var reviewRow: some View {
        HStack(spacing: 14) {
            Text(pending == 1 ? "1 change" : "\(pending) changes")
                .font(.system(size: 14, weight: .medium)).foregroundStyle(Color.ink)
                .contentTransition(.numericText())
            if pending > 1 { HStack(spacing: 0) {
                Button { ws.step(false) } label: { Image(systemName: "chevron.left").frame(width: 22, height: 22).contentShape(Rectangle()) }
                    .help("Previous change (⌘[)")
                Text(index.map { "\($0 + 1) of \(pending)" } ?? "")
                    .font(.system(size: 11.5).monospacedDigit()).foregroundStyle(Color.soft)
                    .frame(minWidth: index == nil ? 0 : 40)
                Button { ws.step(true) } label: { Image(systemName: "chevron.right").frame(width: 22, height: 22).contentShape(Rectangle()) }
                    .help("Next change (⌘])")
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.soft)
            .buttonStyle(.plain) }
            Rectangle().fill(Color(nsColor: Theme.rule)).frame(width: 1, height: 16)
            Button("Revert all") { ws.revert() }
                .buttonStyle(.plain).foregroundStyle(Color.soft)
                .help("Put back every change (⇧⌘⌫)")
            Button { ws.keep() } label: {
                Text("Keep all").foregroundStyle(Color(nsColor: Theme.onAccent))
                    .padding(.horizontal, 11).padding(.vertical, 4)
                    .background(Capsule().fill(Color.accentInk))
            }
            .buttonStyle(Press())
            .help("Keep every change (⇧⌘↩)")
        }
        .font(.system(size: 12.5, weight: .medium))
        .fixedSize()
        .animation(morph, value: index)
    }

    private func listening(_ text: String) -> some View {
        HStack(spacing: 12) {
            Waveform(level: ws.level)
            Text(text.isEmpty ? "Listening…" : text)
                .font(.voice(17))
                .foregroundStyle(text.isEmpty ? Color.soft : Color.ink)
                .lineLimit(1)
                .truncationMode(.head)
                .frame(maxWidth: 440, alignment: .leading)
                .contentTransition(.opacity)
        }
        .fixedSize()
    }

    private func thinking(_ activity: String, _ words: String?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if let words {
                Text(words)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.soft)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Presence().alignmentGuide(.firstTextBaseline) { $0[.bottom] - 3 }
                Text(ws.live.isEmpty ? activity : ws.live)
                    .font(.voice(17).italic(ws.live.isEmpty))
                    .foregroundStyle(ws.live.isEmpty ? Color.soft : Color.ink)
                    .lineLimit(3)
                    .truncationMode(.head)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
                    .animation(.easeOut(duration: 0.12), value: ws.live)
            }
        }
        .frame(width: 440, alignment: .leading)
    }

    private func done(_ n: Int) -> some View {
        Text(n == 0 ? "Nothing to change" : n == 1 ? "1 change" : "\(n) changes")
            .font(.voice(17)).foregroundStyle(Color.soft)
            .fixedSize()
    }

    private func failed(_ message: String) -> some View {
        HStack(spacing: 10) {
            Circle().fill(Color.redInk).frame(width: 7, height: 7)
            Text(message).font(.system(size: 13)).foregroundStyle(Color.ink).lineLimit(3).frame(maxWidth: 420, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if let remedy = ws.remedy {
                Button(remedy.label) {
                    remedy.action()
                    ws.phase = .idle
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accentInk)
            }
            Button { ws.phase = .idle } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)) }
                .buttonStyle(.plain).foregroundStyle(Color.soft)
                .help("Dismiss (esc)")
        }
    }

    private func said(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Circle().fill(Color.accentInk).frame(width: 7, height: 7).padding(.top, 8)
                Reply(text: text)
                Button { ws.phase = .idle } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)) }
                    .buttonStyle(.plain).foregroundStyle(Color.soft).padding(.top, 5)
                    .opacity(hovering ? 1 : 0.4)
                    .help("Dismiss")
            }
            if !ws.sources.isEmpty { Sources(ws: ws).padding(.leading, 19) }
            if pending > 0 { reviewRow.padding(.leading, 19) }
        }
        .padding(.vertical, 1)
        .task(id: shown) {
            guard !hovering else { return }
            let words = Double(text.split(separator: " ").count)
            await dismiss(after: max(5, min(words, 60) * 0.32 + 2.5))
        }
    }

    private var lines: [Line] {
        ws.current.flatMap { ws.transcript[$0] }.map { Array($0.suffix(3)) } ?? []
    }

    private var command: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !lines.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(lines) { line in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.words).font(.system(size: 12)).foregroundStyle(Color.soft).lineLimit(1)
                            Text((try? AttributedString(markdown: line.reply, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(line.reply)).font(.voice(15)).foregroundStyle(line.failed ? Color.redInk : Color.ink)
                                .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(width: 470, alignment: .leading)
                Divider().opacity(0.5)
            }
            if !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(suggestions.enumerated()), id: \.element) { i, m in
                        Button { accept(m) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: m.folder ? "folder" : "doc.text")
                                    .font(.system(size: 11)).foregroundStyle(Color.soft).frame(width: 14)
                                Text(m.url.deletingPathExtension().lastPathComponent).font(.voice(15)).foregroundStyle(Color.ink).lineLimit(1)
                                Text((m.insert.trimmingCharacters(in: CharacterSet(charactersIn: " /")) as NSString).deletingLastPathComponent).font(.system(size: 11)).foregroundStyle(Color.soft)
                                    .lineLimit(1).truncationMode(.head)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(i == pick ? Color.accentInk.opacity(0.1) : .clear))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    Text("Tab to add · Point Quill at a note or folder").font(.system(size: 10.5)).foregroundStyle(Color.soft).padding(.leading, 8).padding(.top, 3)
                }
                .frame(width: 470, alignment: .leading)
                Divider().opacity(0.5)
            }
            HStack(spacing: 10) {
                Image(systemName: "sparkle").font(.system(size: 13, weight: .medium)).foregroundStyle(Color.accentInk)
                if chrome.selectedWords > 0 {
                    Text(chrome.selectedWords == 1 ? "1 word" : "\(chrome.selectedWords) words")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.accentInk)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(Capsule().fill(Color.accentInk.opacity(0.12)))
                        .help("Your request is about the selected text")
                }
                TextField(chrome.selectedWords > 0 ? "Ask about the selection…" : ws.company.isEmpty ? "Ask Quill to change or check something…" : "Ask \(([ws.spec] + ws.company).map(\.name).joined(separator: ", "))…", text: $chrome.draft)
                    .textFieldStyle(.plain)
                    .font(.voice(18))
                    .foregroundStyle(Color.ink)
                    .focused($focused)
                    .frame(width: chrome.selectedWords > 0 ? 380 : 440)
                    .onSubmit {
                        if let m = suggestions[safe: pick] { return accept(m) }
                        let words = chrome.draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !words.isEmpty else { return }
                        chrome.draft = ""
                        chrome.commanding = false
                        chrome.remember(words)
                        ws.ask(words)
                    }
                    .onKeyPress(.upArrow) { suggestions.isEmpty ? step(-1) : move(-1) }
                    .onKeyPress(.downArrow) { suggestions.isEmpty ? step(1) : move(1) }
                    .onKeyPress(.tab) {
                        guard let m = suggestions[safe: pick] else { return .ignored }
                        accept(m)
                        return .handled
                    }
                    .onChange(of: chrome.draft) { pick = 0 }
                    .onExitCommand { chrome.commanding = false }
                Keycap("↩").opacity(chrome.draft.isEmpty ? 0.4 : 1)
            }
        }
        .onAppear { focused = true }
    }

    private var suggestions: [Mention] {
        mentionToken(chrome.draft).map { ws.mentions($0) } ?? []
    }

    private func move(_ delta: Int) -> KeyPress.Result {
        pick = (pick + delta + suggestions.count) % suggestions.count
        return .handled
    }

    private func accept(_ m: Mention) {
        guard let token = mentionToken(chrome.draft) else { return }
        chrome.draft = String(chrome.draft.dropLast(token.count)) + m.insert
        pick = 0
    }

    private func step(_ delta: Int) -> KeyPress.Result {
        let history = chrome.history
        guard !history.isEmpty, delta < 0 || chrome.recall != nil else { return .ignored }
        if chrome.recall == nil { chrome.stash = chrome.draft }
        let next = (chrome.recall ?? history.count) + delta
        guard next >= 0 else { return .handled }
        if next >= history.count {
            chrome.recall = nil
            chrome.draft = chrome.stash
        } else {
            chrome.recall = next
            chrome.draft = history[next]
        }
        return .handled
    }

    private func dismiss(after seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
        while hovering { try? await Task.sleep(for: .milliseconds(300)) }
        guard !Task.isCancelled else { return }
        withAnimation(morph) { ws.phase = .idle }
    }
}

struct Sources: View {
    var ws: Workspace

    var body: some View {
        let shown = Array(ws.sources.prefix(4))
        HStack(spacing: 6) {
            Text("Read").font(.system(size: 11.5)).foregroundStyle(Color.soft)
            ForEach(shown, id: \.self) { url in
                Button { ws.reveal(url) } label: {
                    HStack(spacing: 4) {
                        Image(systemName: (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true ? "folder" : "doc.text").font(.system(size: 10))
                        Text(url.lastPathComponent).lineLimit(1)
                    }
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color.ink)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.ink.opacity(0.06)))
                    .contentShape(Capsule())
                }
                .buttonStyle(Press())
                .help(url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
            }
            if ws.sources.count > shown.count {
                Text("+\(ws.sources.count - shown.count) more").font(.system(size: 11.5)).foregroundStyle(Color.soft)
                    .help(ws.sources.dropFirst(shown.count).map(\.lastPathComponent).joined(separator: ", "))
            }
        }
        .fixedSize()
    }
}

struct Keycap: View {
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(Color.soft)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Color.faint.opacity(0.7), lineWidth: 0.75))
    }
}

struct Waveform: View {
    var level: Float
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2.5) {
                ForEach(0..<5, id: \.self) { i in
                    let wobble = 0.55 + 0.45 * sin(t * 9 + Double(i) * 1.3)
                    Capsule()
                        .fill(Color.accentInk)
                        .frame(width: 3, height: 4 + CGFloat(level) * 16 * wobble)
                }
            }
            .frame(height: 20)
            .animation(.easeOut(duration: 0.08), value: level)
        }
    }
}

struct Reply: View {
    var text: String
    @State private var open = false

    private var styled: AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }

    private var long: Bool { text.count > 360 || text.filter { $0 == "\n" }.count > 4 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if open {
                    ScrollView { prose(nil) }.frame(maxHeight: 320)
                } else {
                    prose(long ? 6 : nil)
                }
            }
            .frame(width: 480, alignment: .leading)
            if long {
                Button(open ? "Show less" : "Show all") { withAnimation(morph) { open.toggle() } }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.soft)
            }
        }
    }

    private func prose(_ limit: Int?) -> some View {
        Text(styled)
            .font(.voice(17))
            .foregroundStyle(Color.ink)
            .lineSpacing(3)
            .lineLimit(limit)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct Presence: View {
    @Environment(\.accessibilityReduceMotion) private var still
    var body: some View {
        TimelineView(.animation(paused: still)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Capsule()
                .fill(Color.accentInk)
                .frame(width: 3, height: 14)
                .opacity(still ? 0.8 : 0.7 + 0.3 * sin(t * .pi / 0.8))
        }
        .frame(width: 3, height: 14)
    }
}

struct Press: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
