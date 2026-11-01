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
    static func serif(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        Brand.serif(size, weight)
    }
}

let enter = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.24)
let morph = Animation.spring(duration: 0.38, bounce: 0.12)

struct Pill: View {
    @Bindable var ws: Workspace
    @Bindable var chrome: Chrome
    @State private var hovering = false
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
                label(n == 1 ? "Editing · 1 change" : "Editing · \(n) changes")
            case .said(let text):
                said(text)
            case .done(let n):
                done(n).task(id: shown) { await dismiss(after: 3.4) }
            case .failed(let message):
                failed(message)
            }
        }
    }

    private func coach(_ source: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This sentence is yours, from “\(source)”. Hold \(Prefs.talkKey.label) and say what you'd change.")
                .font(.serif(18)).foregroundStyle(Color.ink).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button {
                    ws.ask("Make this sentence say what I mean, in my voice.", mode: .guided)
                } label: {
                    HStack(spacing: 8) {
                        Text("Make it say what I mean").font(.serif(17, .medium))
                        Text("⌘↩").font(.system(size: 11, weight: .medium)).opacity(0.7)
                    }
                    .foregroundStyle(Color(nsColor: Theme.paper))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.ink))
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
        HStack(spacing: 14) {
            HStack(spacing: 6) { Keycap(Prefs.talkKey.label); Text("hold to talk") }
            Text("·").foregroundStyle(Color.faint)
            HStack(spacing: 6) { Keycap("⌘K"); Text("type") }
        }
        .font(.system(size: 12))
        .foregroundStyle(Color.soft)
    }

    private var reviewRow: some View {
        HStack(spacing: 12) {
            Circle().fill(Color.accentInk).frame(width: 7, height: 7)
            Text(pending == 1 ? "1 change to review" : "\(pending) changes to review")
                .font(.system(size: 13, weight: .medium)).foregroundStyle(Color.ink)
                .contentTransition(.numericText())
            Text("·").foregroundStyle(Color.faint)
            Button { ws.keep() } label: { HStack(spacing: 5) { Text("Keep all"); Keycap("⇧⌘↩") } }
                .buttonStyle(.plain).foregroundStyle(Color.ink)
            Button { ws.revert() } label: { HStack(spacing: 5) { Text("Revert all"); Keycap("⇧⌘⌫") } }
                .buttonStyle(.plain).foregroundStyle(Color.soft)
        }
        .font(.system(size: 12.5))
        .fixedSize()
    }

    private func listening(_ text: String) -> some View {
        HStack(spacing: 12) {
            Waveform(level: ws.level)
            Text(text.isEmpty ? "Listening…" : text)
                .font(.serif(17))
                .foregroundStyle(text.isEmpty ? Color.soft : Color.ink)
                .lineLimit(1)
                .truncationMode(.head)
                .frame(maxWidth: 440, alignment: .leading)
                .contentTransition(.opacity)
        }
        .fixedSize()
    }

    private func thinking(_ activity: String, _ words: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("“\(words)”")
                .font(.serif(15).italic())
                .foregroundStyle(Color.soft)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 420, alignment: .leading)
            HStack(spacing: 8) {
                Orb()
                Shimmer(text: activity)
            }
        }
        .fixedSize()
    }

    private func label(_ text: String) -> some View {
        HStack(spacing: 9) {
            Orb()
            Text(text).font(.system(size: 13, weight: .medium)).foregroundStyle(Color.ink)
        }
        .fixedSize()
    }

    private func done(_ n: Int) -> some View {
        HStack(spacing: 10) {
            Circle().fill(n == 0 ? Color.soft : Color.accentInk).frame(width: 7, height: 7)
            Text(n == 0 ? "Nothing to change" : n == 1 ? "1 change" : "\(n) changes")
                .font(.system(size: 13, weight: .medium)).foregroundStyle(Color.ink)
            if pending > 0 {
                Text("·").foregroundStyle(Color.faint)
                HStack(spacing: 5) { Keycap("⌘↩"); Text("keep") }
                HStack(spacing: 5) { Keycap("⌘⌫"); Text("revert") }
                HStack(spacing: 5) { Keycap("⌘Z"); Text("undo") }
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(Color.soft)
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
                Text(text)
                    .font(.serif(17))
                    .foregroundStyle(Color.ink)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: 480, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                Button { ws.phase = .idle } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)) }
                    .buttonStyle(.plain).foregroundStyle(Color.soft).padding(.top, 5)
                    .opacity(hovering ? 1 : 0.4)
            }
            if pending > 0 { reviewRow.padding(.leading, 19) }
        }
        .padding(.vertical, 1)
        .task(id: shown) {
            let words = Double(text.split(separator: " ").count)
            await dismiss(after: max(5, words * 0.32 + 2.5))
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
                            Text(line.reply).font(.serif(15)).foregroundStyle(line.failed ? Color.redInk : Color.ink)
                                .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                        }
                    }
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
                TextField(chrome.selectedWords > 0 ? "Ask about the selection…" : "Ask Quill to change or check something…", text: $chrome.draft)
                    .textFieldStyle(.plain)
                    .font(.serif(18))
                    .foregroundStyle(Color.ink)
                    .focused($focused)
                    .frame(width: chrome.selectedWords > 0 ? 380 : 440)
                    .onSubmit {
                        let words = chrome.draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !words.isEmpty else { return }
                        chrome.draft = ""
                        chrome.commanding = false
                        chrome.remember(words)
                        ws.ask(words)
                    }
                    .onKeyPress(.upArrow) { step(-1) }
                    .onKeyPress(.downArrow) { step(1) }
                    .onExitCommand { chrome.commanding = false }
                Keycap("↩").opacity(chrome.draft.isEmpty ? 0.4 : 1)
            }
        }
        .onAppear { focused = true }
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

struct Orb: View {
    @Environment(\.accessibilityReduceMotion) private var still
    var body: some View {
        TimelineView(.animation(paused: still)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let s = 0.75 + 0.25 * (0.5 + 0.5 * sin(t * 4.2))
            Circle()
                .fill(Color.accentInk)
                .frame(width: 7, height: 7)
                .scaleEffect(s)
                .opacity(0.55 + 0.45 * s)
        }
        .frame(width: 8, height: 8)
    }
}

struct Shimmer: View {
    var text: String
    @Environment(\.accessibilityReduceMotion) private var still
    var body: some View {
        if still {
            Text(text).font(.system(size: 13, weight: .medium)).foregroundStyle(Color.ink)
        } else {
            shimmer
        }
    }

    private var shimmer: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.soft)
                .overlay {
                    GeometryReader { g in
                        LinearGradient(colors: [.clear, Color.ink, .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: g.size.width * 0.5)
                            .offset(x: (t * 1.8 - 0.4) * g.size.width)
                    }
                    .mask(Text(text).font(.system(size: 13, weight: .medium)))
                }
                .contentTransition(.opacity)
        }
    }
}

struct Press: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct NoteCard: View {
    var note: MarginNote
    var active: Bool
    var busy: Bool
    var apply: () -> Void
    var dismiss: () -> Void
    var hover: (Bool) -> Void
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let lens = note.lens {
                Text(lens.uppercased())
                    .font(.system(size: 9.5, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(Color.accentInk.opacity(0.8))
            }
            Text(note.note)
                .font(.serif(14.5))
                .foregroundStyle(Color.ink.opacity(0.88))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button("Apply", action: apply).foregroundStyle(Color.accentInk)
                    .disabled(busy)
                    .help(busy ? "Wait for the current request to finish" : "Ask Quill to make this edit")
                Button("Dismiss", action: dismiss).foregroundStyle(Color.soft)
            }
            .font(.system(size: 11.5, weight: .medium))
            .buttonStyle(.plain)
            .opacity(hovering || active ? 1 : 0.5)
        }
        .padding(.leading, 12)
        .overlay(alignment: .leading) {
            Capsule().fill(Color.accentInk.opacity(hovering || active ? 0.9 : 0.35)).frame(width: 2)
        }
        .frame(width: 220, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { hovering = $0; hover($0) }
        .animation(.easeOut(duration: 0.15), value: hovering || active)
    }
}

struct ChangeCard: View {
    var hunk: Hunk
    var keep: () -> Void
    var revert: () -> Void
    var hover: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if hunk.old.isEmpty {
                Text("Added by Quill").font(.system(size: 11, weight: .medium)).foregroundStyle(Color.soft)
            } else {
                Text(hunk.old)
                    .font(.serif(15))
                    .strikethrough(true, color: Color.redInk.opacity(0.7))
                    .foregroundStyle(Color.soft)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(hunk.flags, id: \.self) { flag in
                Label(flag, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.redInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 12) {
                Button(action: keep) { HStack(spacing: 5) { Text("Keep"); Keycap("⌘↩") } }
                    .foregroundStyle(Color.ink)
                Button(action: revert) { HStack(spacing: 5) { Text("Revert"); Keycap("⌘⌫") } }
                    .foregroundStyle(Color.soft)
            }
            .font(.system(size: 12, weight: .medium))
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: 360, alignment: .leading)
        .fixedSize(horizontal: true, vertical: true)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(nsColor: Theme.paper))
            .shadow(color: .black.opacity(0.14), radius: 12, y: 5))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.faint.opacity(0.7), lineWidth: 0.5))
        .padding(12)
        .onHover(perform: hover)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(hunk.old.isEmpty ? "Added text" : "Replaced: \(hunk.old)")
    }
}
