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
        .system(size: size, weight: weight, design: .serif)
    }
}

let enter = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.24)

struct Pill: View {
    @Bindable var ws: Workspace
    @Bindable var chrome: Chrome
    @State private var hovering = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 10) {
            if chrome.choosingMode { ModeChooser(ws: ws, chrome: chrome).transition(.scale(scale: 0.96).combined(with: .opacity)) }
            content
        }
        .animation(enter, value: chrome.choosingMode)
        .animation(enter, value: key)
        .padding(.bottom, 26)
        .frame(maxWidth: .infinity, alignment: .bottom)
    }

    private var key: String {
        if chrome.commanding { return "command" }
        switch ws.phase {
        case .idle: return chrome.hinting ? "hint" : "idle"
        case .listening: return "listening"
        case .thinking: return "thinking"
        case .applying: return "applying"
        case .said(let s): return "said" + s
        case .done: return "done"
        case .failed(let s): return "failed" + s
        }
    }

    @ViewBuilder
    private var content: some View {
        if chrome.commanding {
            command
        } else {
            switch ws.phase {
            case .idle:
                if chrome.hinting { hint.transition(.opacity) }
            case .listening(let text):
                capsule { listening(text) }
            case .thinking(let activity, let words):
                capsule { thinking(activity, words) }
            case .applying(let n):
                capsule { label(dot: .accentInk, n == 1 ? "Editing · 1 change" : "Editing · \(n) changes", pulse: true) }
            case .said(let text):
                said(text)
            case .done(let n):
                capsule { done(n) }
                    .task(id: key) { await dismiss(after: 3.4) }
            case .failed(let message):
                capsule { failed(message) }
                    .task(id: key) { await dismiss(after: 9) }
            }
        }
    }

    private func capsule<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        c()
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .frame(maxWidth: 560)
            .fixedSize(horizontal: true, vertical: true)
            .glassEffect(.regular, in: .capsule)
            .transition(.asymmetric(insertion: .scale(scale: 0.95).combined(with: .opacity), removal: .opacity.animation(.easeOut(duration: 0.14))))
    }

    private var hint: some View {
        HStack(spacing: 14) {
            HStack(spacing: 6) { Keycap("right ⌥"); Text("hold to talk") }
            Text("·").foregroundStyle(Color.faint)
            HStack(spacing: 6) { Keycap("⌘K"); Text("type") }
        }
        .font(.system(size: 12))
        .foregroundStyle(Color.soft)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
        .opacity(0.9)
    }

    private func listening(_ text: String) -> some View {
        HStack(spacing: 12) {
            Waveform(level: ws.level)
            Text(text.isEmpty ? "Listening…" : text)
                .font(.serif(15))
                .foregroundStyle(text.isEmpty ? Color.soft : Color.ink)
                .lineLimit(1)
                .truncationMode(.head)
                .frame(maxWidth: 440, alignment: .leading)
                .contentTransition(.opacity)
        }
    }

    private func thinking(_ activity: String, _ words: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("“\(words)”")
                .font(.serif(13).italic())
                .foregroundStyle(Color.soft)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 420, alignment: .leading)
            HStack(spacing: 8) {
                Orb()
                Shimmer(text: activity)
            }
        }
    }

    private func label(dot: Color, _ text: String, pulse: Bool = false) -> some View {
        HStack(spacing: 9) {
            if pulse { Orb() } else { Circle().fill(dot).frame(width: 7, height: 7) }
            Text(text).font(.system(size: 13, weight: .medium)).foregroundStyle(Color.ink)
        }
    }

    private func done(_ n: Int) -> some View {
        HStack(spacing: 10) {
            Circle().fill(Color.greenInk).frame(width: 7, height: 7)
            Text(n == 0 ? "Nothing to change" : n == 1 ? "1 change" : "\(n) changes")
                .font(.system(size: 13, weight: .medium)).foregroundStyle(Color.ink)
            if n > 0 {
                Text("·").foregroundStyle(Color.faint)
                HStack(spacing: 5) { Keycap("⌘Z"); Text("undo") }
                    .font(.system(size: 12)).foregroundStyle(Color.soft)
            }
        }
    }

    private func failed(_ message: String) -> some View {
        HStack(spacing: 10) {
            Circle().fill(Color.redInk).frame(width: 7, height: 7)
            Text(message).font(.system(size: 13)).foregroundStyle(Color.ink).lineLimit(2).frame(maxWidth: 460, alignment: .leading)
            Button { ws.phase = .idle } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)) }
                .buttonStyle(.plain).foregroundStyle(Color.soft)
        }
    }

    private func said(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle().fill(Color.accentInk).frame(width: 7, height: 7).padding(.top, 8)
            Text(text)
                .font(.serif(15))
                .foregroundStyle(Color.ink)
                .lineSpacing(3)
                .textSelection(.enabled)
                .frame(maxWidth: 480, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Button { ws.phase = .idle } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)) }
                .buttonStyle(.plain).foregroundStyle(Color.soft).padding(.top, 5)
                .opacity(hovering ? 1 : 0.4)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .onHover { hovering = $0 }
        .transition(.asymmetric(insertion: .scale(scale: 0.96, anchor: .bottom).combined(with: .opacity), removal: .opacity.animation(.easeOut(duration: 0.14))))
        .task(id: key) {
            let words = Double(text.split(separator: " ").count)
            await dismiss(after: max(5, words * 0.32 + 2.5))
        }
    }

    private var command: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkle").font(.system(size: 13, weight: .medium)).foregroundStyle(Color.accentInk)
            TextField("Ask Quill to change or check something…", text: $chrome.draft)
                .textFieldStyle(.plain)
                .font(.serif(16))
                .foregroundStyle(Color.ink)
                .focused($focused)
                .frame(width: 440)
                .onSubmit {
                    let words = chrome.draft
                    chrome.draft = ""
                    chrome.commanding = false
                    ws.ask(words)
                }
                .onExitCommand { chrome.commanding = false }
            Keycap("↩")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .capsule)
        .onAppear { focused = true }
    }

    private func dismiss(after seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
        while hovering { try? await Task.sleep(for: .milliseconds(300)) }
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.16)) { ws.phase = .idle }
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
    var body: some View {
        TimelineView(.animation) { context in
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
    var body: some View {
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

struct ModeChooser: View {
    @Bindable var ws: Workspace
    @Bindable var chrome: Chrome

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How should Quill answer you?")
                .font(.serif(16, .semibold)).foregroundStyle(Color.ink)
            HStack(spacing: 10) {
                option(.guided, "Guided", "Edits land in the text while you watch")
                option(.notes, "Notes", "Thoughts in the margin. Edits when you ask")
            }
            Text("Change it any time from the Agent menu.")
                .font(.system(size: 11.5)).foregroundStyle(Color.soft)
        }
        .padding(18)
        .frame(width: 440)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    private func option(_ mode: Mode, _ title: String, _ detail: String) -> some View {
        Button {
            ws.mode = mode
            UserDefaults.standard.set(true, forKey: "choseMode")
            chrome.choosingMode = false
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Spacer()
                    if ws.mode == mode { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Color.accentInk) }
                }
                Text(detail).font(.system(size: 12)).foregroundStyle(Color.soft).fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Color.ink)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.ink.opacity(ws.mode == mode ? 0.07 : 0.03)))
            .contentShape(Rectangle())
        }
        .buttonStyle(Press())
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
    var apply: () -> Void
    var dismiss: () -> Void
    var hover: (Bool) -> Void
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(note.note)
                .font(.system(size: 12.5))
                .foregroundStyle(Color.ink.opacity(0.88))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button("Apply", action: apply).foregroundStyle(Color.accentInk)
                Button("Dismiss", action: dismiss).foregroundStyle(Color.soft)
            }
            .font(.system(size: 11.5, weight: .medium))
            .buttonStyle(.plain)
            .opacity(hovering || active ? 1 : 0)
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
