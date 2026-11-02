import AppKit
import SwiftUI
import QuillCore

struct Place: Identifiable, Hashable {
    var url: URL
    var label: String
    var detail: String
    var id: URL { url }
}

enum Firstrun {
    static let hedges = ["basically", "kind of", "sort of", "really", "just", "maybe", "pretty", "i think", "quite", "very", "probably", "actually"]

    static func places() -> [Place] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var found: [Place] = [Place(url: home.appending(path: "Quill"), label: "A new Quill folder", detail: "~/Quill")]
        var roots = [home, home.appending(path: "Documents"), home.appending(path: "Desktop")]
        roots.append(home.appending(path: "Library/Mobile Documents/iCloud~md~obsidian/Documents"))
        for root in roots {
            let children = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
            for child in children where FileManager.default.fileExists(atPath: child.appending(path: ".obsidian").path) {
                let path = child.path.replacingOccurrences(of: home.path, with: "~")
                found.append(Place(url: child, label: child.lastPathComponent, detail: "Obsidian vault · \(path)"))
            }
        }
        return found
    }

    nonisolated static func census(_ folder: URL) -> (notes: Int, words: Int, titles: [String]) {
        let files = (FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey], options: [.skipsHiddenFiles])?
            .compactMap { $0 as? URL } ?? [])
            .filter { $0.pathExtension.lowercased() == "md" && !$0.lastPathComponent.contains("excalidraw") }
        let bytes = files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        let recent = files.sorted {
            ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
                > ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
        }
        return (files.count, bytes / 6, recent.prefix(9).map { $0.deletingPathExtension().lastPathComponent })
    }

    nonisolated static func sentence(in folders: [URL]) -> (String, String)? {
        var best: (score: Int, text: String, source: String)?
        let journal = /(?i)\/(journal|daily|diary|daily notes|logs?)\//
        let dated = /^\d{4}-\d{2}-\d{2}/
        for folder in folders {
            let key = URLResourceKey.contentModificationDateKey
            let files = (FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [key], options: [.skipsHiddenFiles])?
                .compactMap { $0 as? URL } ?? [])
                .filter { f in
                    f.pathExtension == "md" && f.path.firstMatch(of: journal) == nil && f.lastPathComponent.firstMatch(of: dated) == nil
                        && f.lastPathComponent != "Voice.md" && !f.lastPathComponent.contains("excalidraw")
                }
                .sorted {
                    ((try? $0.resourceValues(forKeys: [key]).contentModificationDate) ?? .distantPast)
                        > ((try? $1.resourceValues(forKeys: [key]).contentModificationDate) ?? .distantPast)
                }
            for f in files.prefix(120) {
                guard let text = try? String(contentsOf: f, encoding: .utf8), isWriting(text) else { continue }
                for s in sentences(in: prose(from: text, lists: false)) {
                    let n = s.split(separator: " ").count
                    guard (12...32).contains(n), !s.contains("http"), !s.contains("`"), !s.contains("|") else { continue }
                    let score = hedged(s).filter(\.hedge).count * 10 - abs(n - 20)
                    if score > (best?.score ?? 0) { best = (score, s, f.deletingPathExtension().lastPathComponent) }
                }
            }
        }
        return best.map { ($0.text, $0.source) }
    }

    nonisolated static func hedged(_ sentence: String) -> [(text: String, hedge: Bool)] {
        var parts: [(String, Bool)] = []
        var rest = Substring(sentence)
        outer: while !rest.isEmpty {
            let lower = rest.lowercased()
            for h in hedges where lower.hasPrefix(h) {
                let end = rest.index(rest.startIndex, offsetBy: h.count)
                let boundary = end == rest.endIndex || !rest[end].isLetter
                let start = parts.last.map { $0.0.last.map { !$0.isLetter } ?? true } ?? true
                if boundary && start {
                    var cut = end
                    while cut < rest.endIndex, rest[cut] == " " { cut = rest.index(after: cut) }
                    parts.append((String(rest[rest.startIndex..<cut]), true))
                    rest = rest[cut...]
                    continue outer
                }
            }
            let next = rest.index(after: rest.startIndex)
            if let last = parts.last, !last.1 { parts[parts.count - 1].0.append(rest[rest.startIndex]) } else { parts.append((String(rest[rest.startIndex]), false)) }
            rest = rest[next...]
        }
        return parts.map { (text: $0.0, hedge: $0.1) }
    }
}

@MainActor
@Observable
final class Firstrunner {
    enum Step: Int, CaseIterable { case overture, folder, voice, talk, cowriter }
    var step: Step = .overture
    var places: [Place]
    var chosen: URL
    var census: [URL: (notes: Int, words: Int, titles: [String])] = [:]
    var lines: [String] = []
    var reading = false
    var read = false
    var learn = true
    var sentence: (text: String, source: String)?
    var heard = ""
    var holding = false
    var spoke = false
    var level: Float = 0
    var deaf = false

    init(current: URL) {
        let found = Firstrun.places()
        places = found
        chosen = found.dropFirst().first?.url ?? current
    }

    func count() {
        for place in places where census[place.url] == nil {
            let url = place.url
            Task.detached {
                let c = Firstrun.census(url)
                await MainActor.run { self.census[url] = c }
            }
        }
    }
}

struct Token: Identifiable, Equatable {
    var id: Int
    var text: String
    var hedge: Bool

    static func split(_ sentence: String) -> [Token] {
        var out: [Token] = []
        for part in Firstrun.hedged(sentence) {
            let words = part.hedge ? [part.text.trimmingCharacters(in: .whitespaces)] : part.text.split(separator: " ").map(String.init)
            for w in words where !w.isEmpty { out.append(Token(id: out.count, text: w, hedge: part.hedge)) }
        }
        return out
    }
}

struct Flow: Layout {
    var gap: CGFloat
    var leading: CGFloat

    private func rows(_ width: CGFloat, _ subviews: Subviews) -> [(items: [(Int, CGSize)], width: CGFloat)] {
        var rows: [(items: [(Int, CGSize)], width: CGFloat)] = [([], 0)]
        for (i, view) in subviews.enumerated() {
            let size = view.sizeThatFits(.unspecified)
            let next = rows[rows.count - 1].width + (rows[rows.count - 1].items.isEmpty ? 0 : gap) + size.width
            if next > width, !rows[rows.count - 1].items.isEmpty { rows.append(([], 0)) }
            let row = rows.count - 1
            rows[row].width += (rows[row].items.isEmpty ? 0 : gap) + size.width
            rows[row].items.append((i, size))
        }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let all = rows(proposal.width ?? .infinity, subviews)
        return CGSize(width: all.map(\.width).max() ?? 0, height: CGFloat(all.count) * leading)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (r, row) in rows(bounds.width, subviews).enumerated() {
            var x = bounds.midX - row.width / 2
            for (i, size) in row.items {
                subviews[i].place(at: CGPoint(x: x, y: bounds.minY + CGFloat(r) * leading + (leading - size.height) / 2), proposal: .unspecified)
                x += size.width + gap
            }
        }
    }
}

struct Blurred: ViewModifier {
    var radius: CGFloat
    func body(content: Content) -> some View { content.blur(radius: radius) }
}

struct Listening: View {
    var color: Color

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3.5) {
                ForEach(0..<5, id: \.self) { i in
                    Circle()
                        .fill(color)
                        .frame(width: 4.5, height: 4.5)
                        .scaleEffect(0.7 + 0.45 * max(0, sin(t * 7 - Double(i) * 0.7)))
                }
            }
        }
    }
}

struct Film: View {
    var run: Firstrunner
    var fallback: String
    var finish: () -> Void
    @State private var beat = 0
    @State private var written = 0.0
    @State private var shown = 0
    @State private var heard = 0
    @State private var tokens: [Token] = []
    @Environment(\.accessibilityReduceMotion) private var still

    private let ask = "cut the hedges"
    private let size: CGFloat = 46

    var body: some View {
        ZStack {
            VStack(spacing: 22) {
                QuillMark(progress: written, ink: Brand.paper).frame(height: 132)
                Text("Quill")
                    .font(Brand.display(40, italic: true))
                    .foregroundStyle(Brand.paper)
                    .opacity(beat >= 1 ? 1 : 0)
                    .offset(y: beat >= 1 ? 0 : 6)
            }
            .opacity(beat >= 2 ? 0 : 1)
            .scaleEffect(beat >= 2 ? 0.92 : 1)
            .blur(radius: beat >= 2 ? 8 : 0)
            .offset(y: beat >= 2 ? -40 : 0)

            VStack(spacing: 44) {
                Flow(gap: size * 0.26, leading: size * 1.22) {
                    ForEach(visible) { token in
                        Text(spelled(token))
                            .font(Brand.display(size))
                            .foregroundStyle(token.hedge && beat >= 4 ? Brand.faint : Brand.paper)
                            .overlay(alignment: .leading) {
                                if token.hedge {
                                    Capsule()
                                        .fill(Brand.ember)
                                        .frame(height: 3)
                                        .scaleEffect(x: beat >= 4 ? 1 : 0, anchor: .leading)
                                        .padding(.horizontal, -4)
                                        .offset(y: size * 0.02)
                                }
                            }
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .modifier(active: Blurred(radius: 10), identity: Blurred(radius: 0))),
                                removal: .opacity.combined(with: .scale(scale: 0.6, anchor: .center))
                            ))
                    }
                }
                .frame(maxWidth: 900)
                pill
            }
            .padding(.horizontal, 60)
            .opacity(beat >= 7 ? 0 : 1)
            .scaleEffect(beat >= 7 ? 0.96 : 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottomTrailing) {
            Button("Skip intro") { finish() }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Brand.faint)
                .keyboardShortcut(.cancelAction)
                .padding(28)
        }
        .task { await play() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Quill. Say a change and watch it happen.")
    }

    private var visible: [Token] {
        Array(tokens.prefix(shown)).filter { !($0.hedge && beat >= 5) }
    }

    private func spelled(_ token: Token) -> String {
        guard beat >= 5, tokens.first?.hedge == true, token.id == tokens.first(where: { !$0.hedge })?.id else { return token.text }
        return token.text.prefix(1).uppercased() + token.text.dropFirst()
    }

    private var pill: some View {
        HStack(spacing: 14) {
            if beat >= 5 {
                Circle().fill(Brand.ember).frame(width: 6, height: 6)
                Text("Cut the hedges.").font(Brand.serif(19)).foregroundStyle(Brand.paper)
                Rectangle().fill(Brand.rule).frame(width: 1, height: 16)
                Text(beat >= 6 ? "Kept" : "Keep")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(beat >= 6 ? Brand.paper : Brand.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(beat >= 6 ? Brand.paper.opacity(0.12) : Brand.paper))
                    .contentTransition(.opacity)
            } else {
                Listening(color: Brand.ember)
                Text(String(ask.prefix(heard)))
                    .font(Brand.serif(19))
                    .foregroundStyle(Brand.paper)
                    .frame(minWidth: 150, alignment: .leading)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 46)
        .background(Capsule().fill(Brand.paper.opacity(0.07)))
        .overlay(Capsule().strokeBorder(Brand.paper.opacity(0.12), lineWidth: 1))
        .opacity(beat >= 3 && beat < 7 ? 1 : 0)
        .offset(y: beat >= 3 ? 0 : 14)
        .animation(Brand.ease, value: beat)
    }

    private func at(_ ms: Int) async { try? await Task.sleep(for: .milliseconds(ms)) }

    private func play() async {
        if still {
            finish()
            return
        }
        await at(300)
        withAnimation(.timingCurve(0.45, 0.05, 0.35, 1, duration: 1.9)) { written = 1 }
        await at(1500)
        withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.9)) { beat = 1 }
        await at(1500)
        tokens = Token.split(run.sentence?.text ?? fallback)
        withAnimation(.timingCurve(0.6, 0, 0.3, 1, duration: 0.7)) { beat = 2 }
        await at(450)
        for i in tokens.indices {
            withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.5)) { shown = i + 1 }
            await at(55)
        }
        await at(500)
        withAnimation(Brand.ease) { beat = 3 }
        await at(350)
        for i in ask.indices {
            heard = ask.distance(from: ask.startIndex, to: i) + 1
            await at(48)
        }
        await at(500)
        withAnimation(.timingCurve(0.6, 0, 0.3, 1, duration: 0.5)) { beat = 4 }
        await at(900)
        withAnimation(.spring(response: 0.55, dampingFraction: 0.86)) { beat = 5 }
        await at(1400)
        withAnimation(.easeOut(duration: 0.2)) { beat = 6 }
        await at(900)
        withAnimation(.timingCurve(0.6, 0, 0.3, 1, duration: 0.6)) { beat = 7 }
        await at(450)
        finish()
    }
}

struct TalkCap: View {
    var key: TalkKey
    var down: Bool
    var level: Float

    var body: some View {
        let glyph = switch key {
        case .rightOption: "⌥"
        case .rightCommand: "⌘"
        case .fn: "fn"
        }
        VStack(spacing: 4) {
            Text(glyph).font(.system(size: 30))
            if key != .fn { Text("right").font(.system(size: 10.5, weight: .medium)).opacity(0.7) }
        }
        .foregroundStyle(down ? Color(nsColor: Theme.paper) : Color.ink)
        .frame(width: 88, height: 88)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(down ? Color.accentInk : Color.sheet))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(down ? Color.accentInk : Color.rule, lineWidth: 1))
        .overlay(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.ink.opacity(down ? 0 : 0.06))
                .frame(height: 4)
                .padding(.horizontal, 10)
                .offset(y: 3)
        }
        .shadow(color: Color.accentInk.opacity(down ? 0.25 + Double(min(level, 1)) * 0.35 : 0), radius: 22, y: 6)
        .scaleEffect(down ? 0.96 : 1)
        .offset(y: down ? 2 : 0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: down)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(key.title)
    }
}

struct Miniature<Page: View, Pill: View>: View {
    var titles: [String]
    var selected: Int?
    var agent: AgentSpec?
    @ViewBuilder var page: Page
    @ViewBuilder var pill: Pill

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    ForEach(0..<3, id: \.self) { _ in Circle().fill(Color.ink.opacity(0.12)).frame(width: 10, height: 10) }
                }
                .padding(.bottom, 22)
                .padding(.leading, 4)
                ForEach(Array(titles.prefix(12).enumerated()), id: \.offset) { i, title in
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text").font(.system(size: 10.5)).foregroundStyle(Color.soft)
                        Text(title).font(Brand.serif(14)).foregroundStyle(Color.ink).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(i == selected ? Color.ink.opacity(0.07) : .clear))
                    .transition(.opacity.combined(with: .offset(x: -6)))
                }
                Spacer(minLength: 0)
                if let agent {
                    HStack(spacing: 8) {
                        Mark(spec: agent, size: 14)
                        Text(agent.name).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.ink)
                    }
                    .padding(.leading, 6)
                    .padding(.bottom, 16)
                    .id(agent.id)
                    .transition(.opacity.combined(with: .offset(y: 4)))
                }
            }
            .padding(.top, 16)
            .padding(.horizontal, 10)
            .frame(width: 190, alignment: .leading)
            .background(Color.sheet.opacity(0.6))
            Rectangle().fill(Color.rule).frame(width: 1)
            ZStack(alignment: .bottomLeading) {
                page
                    .frame(width: 290, alignment: .leading)
                    .padding(.top, 56)
                    .padding(.leading, 40)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                pill.padding(.leading, 28).padding(.bottom, 24)
            }
        }
        .background(Color(nsColor: Theme.paper))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.rule, lineWidth: 1))
        .shadow(color: .black.opacity(0.08), radius: 24, y: 10)
        .animation(Brand.ease, value: titles)
        .animation(Brand.ease, value: agent?.id)
    }
}

struct Onboarding: View {
    @Bindable var ws: Workspace
    var run: Firstrunner
    var finish: ((sentence: String, source: String)?) -> Void
    @Environment(\.accessibilityReduceMotion) private var still
    @State private var listener = Listener()
    @State private var monitor: Any?
    @State private var shown = 0

    private let sample = "We are basically trying to kind of build a tool that maybe helps people write better, in a way."
    private var steps: [Firstrunner.Step] { run.learn ? [.folder, .voice, .talk, .cowriter] : [.folder, .talk, .cowriter] }
    private var sentence: String { run.sentence?.text ?? sample }

    var body: some View {
        ZStack {
            Brand.ink.ignoresSafeArea()
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            EllipticalGradient(colors: [Brand.ember.opacity(0.16), Brand.ember.opacity(0.04), .clear], center: .init(x: 0.5, y: 1.05), startRadiusFraction: 0, endRadiusFraction: 0.75)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            if run.step == .overture {
                Film(run: run, fallback: sample) { go(.folder) }
                    .transition(.opacity)
            } else {
                sheet.transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.96)).combined(with: .offset(y: 24)),
                    removal: .opacity
                ))
            }
        }
        .onAppear {
            run.count()
            findSentence()
            listen()
        }
        .onDisappear {
            if let monitor { NSEvent.removeMonitor(monitor) }
            listener.cancel()
        }
    }

    private var sheet: some View {
        GeometryReader { geo in
            let w = min(1000, geo.size.width - 80)
            let h = min(560, geo.size.height - 80)
            let wide = w >= 840
            ZStack(alignment: .topLeading) {
                Color(nsColor: Theme.color(0xFBF8F4, 0x211E1B))
                if wide {
                    preview
                        .frame(width: 680, height: h - 56)
                        .offset(x: 452, y: 64)
                        .id(run.step)
                        .transition(.opacity)
                }
                left
                    .frame(width: wide ? 380 : w - 96, alignment: .leading)
                    .frame(maxHeight: .infinity, alignment: .topLeading)
                    .padding(.leading, 48)
                    .padding(.top, 64)
                    .padding(.bottom, 40)
                progress.padding(.horizontal, 24).padding(.top, 22)
            }
            .frame(width: w, height: h)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            .shadow(color: .black.opacity(0.45), radius: 50, y: 30)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
    }

    private var progress: some View {
        let at = Double((steps.firstIndex(of: run.step) ?? 0) + 1) / Double(steps.count)
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.ink.opacity(0.07))
                Capsule().fill(Brand.ember).frame(width: geo.size.width * at)
            }
        }
        .frame(height: 3)
        .animation(.spring(response: 0.6, dampingFraction: 0.85), value: run.step)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \((steps.firstIndex(of: run.step) ?? 0) + 1) of \(steps.count)")
    }

    private var left: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                switch run.step {
                case .overture, .folder: folder
                case .voice: voice
                case .talk: talk
                case .cowriter: cowriter
                }
            }
            .id(run.step)
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .offset(y: 10)).animation(Brand.ease.delay(0.06)),
                removal: .opacity.animation(.easeOut(duration: 0.12))
            ))
            Spacer(minLength: 20)
            HStack(spacing: 20) {
                Primary(label: primaryLabel, action: advance)
                if let back = previous {
                    Button("Back") { go(back) }
                        .buttonStyle(.plain)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.soft)
                        .keyboardShortcut("[", modifiers: .command)
                }
                Spacer()
                Button("Skip setup") { done() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.faint)
                    .keyboardShortcut(.cancelAction)
            }
        }
    }

    private var primaryLabel: String {
        switch run.step {
        case .cowriter: "Open my first edit"
        case .talk: run.spoke ? "Continue" : "Skip for now"
        default: "Continue"
        }
    }

    private func advance() {
        switch run.step {
        case .overture, .folder:
            ws.switchVault(run.chosen)
            if run.learn { readNotes() }
            go(run.learn ? .voice : .talk)
        case .cowriter: done()
        default: if let next { go(next) }
        }
    }

    private var previous: Firstrunner.Step? {
        guard let i = steps.firstIndex(of: run.step), i > 0 else { return nil }
        return steps[i - 1]
    }

    private var next: Firstrunner.Step? {
        guard let i = steps.firstIndex(of: run.step), i + 1 < steps.count else { return nil }
        return steps[i + 1]
    }

    private func heading(_ text: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(text).font(Brand.display(40)).foregroundStyle(Color.ink).fixedSize(horizontal: false, vertical: true)
            Text(body).font(.system(size: 14.5)).foregroundStyle(Color.soft).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 26)
    }

    private func row<Lead: View>(on: Bool, enabled: Bool = true, @ViewBuilder lead: () -> Lead, label: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                lead().frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Color.ink)
                    Text(detail).font(.system(size: 12)).foregroundStyle(Color.soft).lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.accentInk)
                    .opacity(on ? 1 : 0)
                    .scaleEffect(on ? 1 : 0.6)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(on ? Color.ink.opacity(0.055) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(Press())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .padding(.horizontal, -12)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: on)
    }

    private var folder: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading("Where do you write?", "Quill edits the Markdown files in one folder. They stay where they are, readable by any app.")
            VStack(alignment: .leading, spacing: 2) {
                ForEach(run.places.prefix(4)) { place in
                    let notes = run.census[place.url].map { $0.notes > 0 ? "\($0.notes) notes" : "Empty" } ?? "Counting…"
                    row(on: run.chosen == place.url, lead: {
                        Image(systemName: place.detail.hasPrefix("Obsidian") ? "books.vertical" : "folder")
                            .font(.system(size: 13)).foregroundStyle(Color.soft)
                    }, label: place.label, detail: notes) {
                        run.chosen = place.url
                    }
                }
                Button { choose() } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "plus").font(.system(size: 12, weight: .medium)).frame(width: 18)
                        Text("Another folder…").font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(Color.soft)
                    .padding(.vertical, 9)
                }
                .buttonStyle(.plain)
            }
            Toggle(isOn: Binding(get: { run.learn }, set: { run.learn = $0 })) {
                Text("Learn my voice from these notes").font(.system(size: 13)).foregroundStyle(Color.ink)
            }
            .toggleStyle(.checkbox)
            .padding(.top, 14)
        }
    }

    private var voice: some View {
        let notes = run.census[run.chosen]?.notes ?? 0
        return heading("This is how you write.", run.reading ? "Reading your notes…" : "Quill read \(notes) notes and kept what makes them yours. It sharpens this every time you keep or undo an edit.")
    }

    private var talk: some View {
        let key = Prefs.talkKey
        return VStack(alignment: .leading, spacing: 0) {
            heading("Hold \(key.word) and talk.", "Say the change you want. Let go, and your co-writer makes it.")
            HStack(spacing: 18) {
                TalkCap(key: key, down: run.holding, level: run.level)
                VStack(alignment: .leading, spacing: 6) {
                    if run.deaf {
                        Text("Quill needs the microphone.").font(.system(size: 13)).foregroundStyle(Color.ink)
                        Button("Open Privacy Settings") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
                        }
                        .buttonStyle(.plain).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Color.accentInk)
                    } else if run.spoke {
                        Label("Heard you", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.accentInk)
                        Text("That is the whole gesture.").font(.system(size: 13)).foregroundStyle(Color.soft)
                    } else {
                        Text(run.holding ? "Listening…" : "Try it now").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.ink)
                        Text(run.holding ? "Let go when you’re done." : "Press and hold the key.").font(.system(size: 13)).foregroundStyle(Color.soft)
                    }
                }
                .animation(.easeOut(duration: 0.2), value: run.holding)
            }
        }
    }

    private var cowriter: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading("Who writes with you?", "Quill signs in through the tool you pick, so the plan you already pay for works.")
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(AgentSpec.all.filter { !$0.api || ws.available($0) == true }) { spec in
                        let ready = ws.available(spec)
                        row(on: ws.agentID == spec.id, enabled: ready != false, lead: { Mark(spec: spec, size: 16) },
                            label: spec.name, detail: ready == false ? spec.missing : spec.detail) {
                            ws.agentID = spec.id
                        }
                    }
                }
                .padding(.horizontal, 12)
            }
            .padding(.horizontal, -12)
            .scrollIndicators(.never)
            .frame(maxHeight: 196)
            .mask(LinearGradient(stops: [.init(color: .white, location: 0.85), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
            HStack(spacing: 12) {
                if !ws.models.isEmpty {
                    Picker("", selection: Binding(get: { ws.model?.id ?? "" }, set: { ws.choose(model: $0) })) {
                        ForEach(ws.models) { m in Text(m.name).tag(m.id) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                Picker("", selection: $ws.mode) {
                    Text("Edits").tag(Mode.guided)
                    Text("Margin notes").tag(Mode.notes)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
            }
            .controlSize(.small)
            .padding(.top, 12)
        }
        .onAppear { ws.checkAgents() }
    }

    @ViewBuilder private var preview: some View {
        let titles = run.census[run.chosen]?.titles ?? []
        switch run.step {
        case .overture, .folder:
            Miniature(titles: titles, selected: titles.isEmpty ? nil : 0, agent: nil) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(titles.first ?? "Untitled").font(.system(size: 22, weight: .bold)).foregroundStyle(Color.ink).lineLimit(1)
                    ForEach([0.94, 0.88, 0.97, 0.62], id: \.self) { f in
                        GeometryReader { g in Capsule().fill(Color.ink.opacity(0.07)).frame(width: g.size.width * f) }.frame(height: 8)
                    }
                }
            } pill: { EmptyView() }
        case .voice:
            Miniature(titles: ["Voice"] + titles, selected: 0, agent: nil) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Voice").font(.system(size: 22, weight: .bold)).foregroundStyle(Color.ink)
                    ForEach(Array(run.lines.prefix(5).enumerated()), id: \.offset) { _, line in
                        Text(line).font(.system(size: 13.5)).foregroundStyle(Color.ink).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                            .transition(.opacity.combined(with: .offset(y: 6)))
                    }
                    if run.lines.isEmpty {
                        ForEach([0.9, 0.7, 0.8], id: \.self) { f in
                            GeometryReader { g in Capsule().fill(Color.ink.opacity(0.07)).frame(width: g.size.width * f) }.frame(height: 8)
                        }
                    }
                }
                    } pill: { EmptyView() }
        case .talk:
            Miniature(titles: ["Your first edit"] + titles, selected: 0, agent: nil) {
                page(sentence, edited: false)
            } pill: {
                HStack(spacing: 10) {
                    if run.holding { Listening(color: Color.accentInk) } else { Circle().fill(Color.faint).frame(width: 6, height: 6) }
                    Text(run.heard.isEmpty ? (run.holding ? "Listening…" : "hold \(Prefs.talkKey.label) to talk") : run.heard)
                        .font(Brand.serif(16))
                        .foregroundStyle(run.heard.isEmpty ? Color.soft : Color.ink)
                        .lineLimit(1)
                }
                .padding(.horizontal, 16)
                .frame(height: 36)
                .animation(.easeOut(duration: 0.15), value: run.heard)
            }
        case .cowriter:
            Miniature(titles: ["Your first edit"] + titles, selected: 0, agent: ws.spec) {
                page(sentence, edited: true)
            } pill: {
                HStack(spacing: 12) {
                    Circle().fill(Color.accentInk).frame(width: 6, height: 6)
                    Text("Cut the hedges from the opening.").font(Brand.serif(16)).foregroundStyle(Color.ink)
                    Text("Keep").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Color(nsColor: Theme.paper))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(Color.ink))
                }
                .padding(.horizontal, 16)
                .frame(height: 38)
            }
        }
    }

    private func page(_ text: String, edited: Bool) -> some View {
        let clean = Firstrun.hedged(text).filter { !$0.hedge }.map(\.text).joined()
        let shown = edited ? clean.prefix(1).uppercased() + clean.dropFirst() : text
        return VStack(alignment: .leading, spacing: 14) {
            Text("Your first edit").font(.system(size: 22, weight: .bold)).foregroundStyle(Color.ink)
            Text(shown)
                .font(.system(size: 14))
                .foregroundStyle(Color.ink)
                .lineSpacing(6)
                .underline(edited, color: Color.accentInk.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
                .overlay(alignment: .leading) {
                    if edited { Capsule().fill(Color.accentInk.opacity(0.7)).frame(width: 2).padding(.vertical, 2).offset(x: -16) }
                }
            ForEach([0.92, 0.84], id: \.self) { f in
                GeometryReader { g in Capsule().fill(Color.ink.opacity(0.07)).frame(width: g.size.width * f) }.frame(height: 8)
            }
        }
    }

    private func go(_ step: Firstrunner.Step) {
        withAnimation(still ? nil : .spring(response: 0.6, dampingFraction: 0.9)) { run.step = step }
    }

    private func listen() {
        listener.onPartial = { text in run.heard = text }
        listener.onLevel = { level in Task { @MainActor in run.level = level } }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { event in
            guard run.step == .talk else { return event }
            let key = Prefs.talkKey
            guard event.keyCode == key.keyCode else { return event }
            let raw = event.modifierFlags.rawValue
            let down: Bool = switch key {
            case .rightOption: raw & 0x40 != 0
            case .rightCommand: raw & 0x10 != 0
            case .fn: event.modifierFlags.contains(.function)
            }
            if down, !run.holding { hear() } else if !down, run.holding { heard() }
            return nil
        }
    }

    private func hear() {
        run.holding = true
        run.heard = ""
        Task {
            guard await Listener.authorize() else {
                run.deaf = true
                run.holding = false
                return
            }
            run.deaf = false
            guard run.holding else { return }
            try? await listener.start()
        }
    }

    private func heard() {
        run.holding = false
        run.level = 0
        Task {
            let words = await listener.stop()
            if !words.isEmpty {
                run.heard = words
                withAnimation(Brand.ease) { run.spoke = true }
            }
        }
    }

    private func findSentence() {
        guard run.sentence == nil else { return }
        let folders = [run.chosen] + ws.voiceSources
        Task {
            let picked = await Task.detached { Firstrun.sentence(in: folders) }.value
            if let picked { run.sentence = (text: picked.0, source: picked.1) }
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if !run.places.contains(where: { $0.url == url }) {
            run.places.append(Place(url: url, label: url.lastPathComponent, detail: url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")))
        }
        run.chosen = url
        run.count()
    }

    private func readNotes() {
        run.reading = true
        Task {
            let found = describe(await ws.measure())
            run.reading = false
            for line in found {
                withAnimation(still ? nil : Brand.ease) { run.lines.append(line) }
                try? await Task.sleep(for: .milliseconds(still ? 0 : 260))
            }
            run.read = true
        }
    }

    private func done() {
        if let s = run.sentence { return finish((sentence: s.text, source: s.source)) }
        finish(nil)
    }
}
