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
    static func places() -> [Place] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var found: [Place] = [Place(url: home.appending(path: "Quill"), label: "A new Quill folder", detail: "~/Quill")]
        var roots = [home, home.appending(path: "Documents"), home.appending(path: "Desktop")]
        let icloud = home.appending(path: "Library/Mobile Documents/iCloud~md~obsidian/Documents")
        roots.append(icloud)
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
        let hedges = ["basically", "kind of", "sort of", "really", "just", "maybe", "pretty", "i think", "quite", "very", "probably", "actually"]
        var best: (score: Int, text: String, source: String)?
        for folder in folders {
            let files = (FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])?
                .compactMap { $0 as? URL } ?? [])
                .filter { $0.pathExtension == "md" && !$0.path.contains("/Journal/") && $0.lastPathComponent != "Voice.md" && !$0.lastPathComponent.contains("excalidraw") }
            for f in files.prefix(800) {
                guard let text = try? String(contentsOf: f, encoding: .utf8), isWriting(text) else { continue }
                for s in sentences(in: prose(from: text, lists: false)) {
                    let n = s.split(separator: " ").count
                    guard (12...32).contains(n), !s.contains("http"), !s.contains("`"), !s.contains("|") else { continue }
                    let lower = s.lowercased()
                    let score = hedges.filter { lower.contains($0) }.count * 10 - abs(n - 20)
                    if score > (best?.score ?? 0) { best = (score, s, f.deletingPathExtension().lastPathComponent) }
                }
            }
        }
        return best.map { ($0.text, $0.source) }
    }
}

@MainActor
@Observable
final class Firstrunner {
    enum Step: Int { case overture, folder, voice, cowriter }
    var step: Step = .overture
    var places: [Place]
    var chosen: URL
    var census: [URL: (notes: Int, words: Int, titles: [String])] = [:]
    var lines: [String] = []
    var reading = false
    var read = false

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

enum Proof {
    static let paper = Color(red: 0.949, green: 0.933, blue: 0.898)
    static let sheet = Color(red: 0.988, green: 0.982, blue: 0.965)
    static let ink = Color(red: 0.11, green: 0.106, blue: 0.098)
    static let pencil = Color(red: 0.2, green: 0.33, blue: 0.86)
    static let ease = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.6)

    static func slug(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .tracking(1.4)
            .foregroundStyle(ink.opacity(0.5))
    }
}

struct Grain: View {
    var body: some View {
        Canvas { ctx, size in
            var rng = SplitMix(seed: 7)
            let count = Int(size.width * size.height / 90)
            for _ in 0..<count {
                let x = Double(rng.next() % 10_000) / 10_000 * size.width
                let y = Double(rng.next() % 10_000) / 10_000 * size.height
                let dark = rng.next() % 2 == 0
                ctx.fill(Path(CGRect(x: x, y: y, width: 1, height: 1)), with: .color(dark ? Proof.ink.opacity(0.05) : .white.opacity(0.35)))
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

struct CropMarks: View {
    var body: some View {
        Canvas { ctx, size in
            let gap: CGFloat = 8, len: CGFloat = 14, o: CGFloat = 30
            var p = Path()
            for (x, y, sx, sy) in [(o, o, -1.0, -1.0), (size.width - o, o, 1, -1), (o, size.height - o, -1, 1), (size.width - o, size.height - o, 1, 1)] {
                p.move(to: CGPoint(x: x + sx * gap, y: y))
                p.addLine(to: CGPoint(x: x + sx * (gap + len), y: y))
                p.move(to: CGPoint(x: x, y: y + sy * gap))
                p.addLine(to: CGPoint(x: x, y: y + sy * (gap + len)))
            }
            ctx.stroke(p, with: .color(Proof.ink.opacity(0.35)), lineWidth: 0.75)
        }
        .padding(-30)
        .allowsHitTesting(false)
    }
}

struct PencilStrike: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX - 4, y: r.midY + 3))
        p.addCurve(to: CGPoint(x: r.maxX + 6, y: r.midY - 2),
                   control1: CGPoint(x: r.minX + r.width * 0.35, y: r.midY - 1),
                   control2: CGPoint(x: r.minX + r.width * 0.7, y: r.midY + 2))
        return p
    }
}

struct Caret: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.midX, y: r.minY), control: CGPoint(x: r.minX + r.width * 0.3, y: r.midY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.maxY), control: CGPoint(x: r.maxX - r.width * 0.3, y: r.midY))
        return p
    }
}

struct Overture: View {
    var begin: () -> Void
    @State private var phase = 0
    @Environment(\.accessibilityReduceMotion) private var still

    private let size: CGFloat = 76
    private let lead = "Write like "
    private let cut = "everyone else"
    private let kept = "yourself"

    var body: some View {
        let font = Theme.serif(size)
        let cutWidth = Theme.width(cut, font)
        let keptWidth = Theme.width(kept, font)
        VStack(alignment: .leading, spacing: 0) {
            Proof.slug("Galley 1 · First proof")
                .padding(.bottom, 28)
                .opacity(phase >= 1 ? 1 : 0)
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(lead)
                ZStack(alignment: .bottomLeading) {
                    Text(cut)
                        .foregroundStyle(Proof.ink.opacity(phase >= 2 ? 0.55 : 1))
                        .fixedSize()
                        .overlay {
                            PencilStrike()
                                .trim(from: 0, to: phase >= 2 ? 1 : 0)
                                .stroke(Proof.pencil, style: StrokeStyle(lineWidth: 3.2, lineCap: .round))
                                .offset(y: -size * 0.04)
                        }
                        .opacity(phase >= 4 ? 0 : 1)
                    Caret()
                        .trim(from: 0, to: phase >= 3 ? 1 : 0)
                        .stroke(Proof.pencil, style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
                        .frame(width: size * 0.26, height: size * 0.3)
                        .offset(x: -size * 0.16, y: size * 0.12)
                        .opacity(phase == 3 ? 1 : 0)
                    Text(kept)
                        .italic(phase < 4)
                        .foregroundStyle(phase >= 4 ? Proof.ink : Proof.pencil)
                        .fixedSize()
                        .scaleEffect(phase >= 4 ? 1 : 0.5, anchor: .bottomLeading)
                        .offset(y: phase >= 4 ? 0 : -size * 0.92)
                        .opacity(phase >= 3 ? 1 : 0)
                        .mask(alignment: .bottomLeading) {
                            Rectangle().frame(width: phase >= 3 ? keptWidth * 1.2 : 0, height: size * 3)
                        }
                }
                .frame(width: phase >= 4 ? keptWidth : cutWidth, alignment: .leading)
                Text(".")
                Spacer(minLength: 40)
                HStack(spacing: 10) {
                    Text(kept).font(.serif(26).italic())
                    Text("/").font(.serif(30))
                }
                .foregroundStyle(Proof.pencil)
                .opacity(phase >= 4 ? 0.4 : phase >= 3 ? 1 : 0)
                .offset(y: -size * 0.12)
                .accessibilityHidden(true)
            }
            .font(.serif(size))
            .foregroundStyle(Proof.ink)
            .opacity(phase >= 1 ? 1 : 0)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Write like yourself.")
            Text("A co-writer that edits in front of you, keeps what’s yours, and learns your voice from your own notes.")
                .font(.serif(21))
                .foregroundStyle(Proof.ink.opacity(0.62))
                .lineSpacing(5)
                .frame(width: 560, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 26)
                .opacity(phase >= 5 ? 1 : 0)
                .offset(y: phase >= 5 ? 0 : 8)
            Primary(label: "Begin", action: begin)
                .padding(.top, 40)
                .opacity(phase >= 5 ? 1 : 0)
                .offset(y: phase >= 5 ? 0 : 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 96)
        .task { await play() }
    }

    private func play() async {
        if still { phase = 5; return }
        let beats: [(Int, Int, Animation)] = [
            (1, 350, .easeOut(duration: 0.7)),
            (2, 1100, .timingCurve(0.6, 0, 0.3, 1, duration: 0.55)),
            (3, 650, .timingCurve(0.3, 0, 0.2, 1, duration: 0.7)),
            (4, 1300, .timingCurve(0.23, 1, 0.32, 1, duration: 0.8)),
            (5, 500, .timingCurve(0.23, 1, 0.32, 1, duration: 0.7)),
        ]
        for (target, wait, animation) in beats {
            try? await Task.sleep(for: .milliseconds(wait))
            withAnimation(animation) { phase = target }
        }
    }
}

struct Primary: View {
    var label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(label).font(.system(size: 14, weight: .semibold))
                Text("↩").font(.system(size: 12, weight: .medium)).opacity(0.55)
            }
            .foregroundStyle(Proof.sheet)
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .background(Capsule().fill(Proof.ink))
        }
        .buttonStyle(Press())
        .keyboardShortcut(.defaultAction)
    }
}

struct Onboarding: View {
    @Bindable var ws: Workspace
    var run: Firstrunner
    var finish: ((sentence: String, source: String)?) -> Void
    @Environment(\.accessibilityReduceMotion) private var still

    private let names = ["", "The folder", "Your voice", "The co-writer"]

    var body: some View {
        ZStack {
            Proof.paper.ignoresSafeArea()
            Grain()
            Group {
                switch run.step {
                case .overture: Overture { go(.folder) }
                case .folder: split(1, folder, page: folderPage, slug: run.places.first { $0.url == run.chosen }?.label ?? "Folder")
                case .voice: split(2, voice, page: voicePage, slug: "Voice.md")
                case .cowriter: split(3, cowriter, page: cowriterPage, slug: "Your first edit")
                }
            }
            .id(run.step)
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .offset(y: 12)).animation(Proof.ease.delay(0.06)),
                removal: .opacity.animation(.easeOut(duration: 0.16))
            ))
            VStack {
                HStack(alignment: .firstTextBaseline) {
                    (Text("Quill").foregroundColor(Proof.ink) + Text(".").foregroundColor(Proof.pencil))
                        .font(.serif(20, .semibold))
                    Spacer()
                    if run.step != .overture {
                        Button("Skip setup") { done(nil) }
                            .buttonStyle(.plain)
                            .font(.system(size: 12))
                            .foregroundStyle(Proof.ink.opacity(0.5))
                            .keyboardShortcut(.cancelAction)
                    }
                }
                Spacer()
                HStack {
                    Proof.slug(run.step == .overture ? "Press ↩ to begin" : "Your files stay where they are")
                    Spacer()
                    Proof.slug(run.step == .overture ? "Quill · Nº 1" : "\(run.step.rawValue) / 3")
                }
                .padding(.top, 12)
                .overlay(alignment: .top) { Rectangle().fill(Proof.ink.opacity(0.14)).frame(height: 0.75) }
            }
            .padding(.top, 34)
            .padding(.bottom, 22)
            .padding(.horizontal, 40)
        }
        .preferredColorScheme(.light)
        .onAppear { run.count() }
    }

    private func split<L: View, R: View>(_ n: Int, _ left: L, page: R, slug: String) -> some View {
        HStack(alignment: .center, spacing: 88) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    ForEach(1...3, id: \.self) { i in
                        Rectangle()
                            .fill(i < n ? Proof.ink : i == n ? Proof.pencil : Proof.ink.opacity(0.15))
                            .frame(width: 28, height: 2)
                    }
                }
                .padding(.bottom, 18)
                Proof.slug(String(format: "%02d — %@", n, names[n]))
                    .padding(.bottom, 16)
                left
            }
            .frame(width: 400, alignment: .leading)
            VStack(alignment: .leading, spacing: 38) {
                Proof.slug("Proof · \(slug)")
                page
                    .frame(width: 380, height: 470, alignment: .topLeading)
                    .background(Proof.sheet)
                    .clipShape(Rectangle())
                    .shadow(color: Proof.ink.opacity(0.10), radius: 0.5, y: 0.5)
                    .shadow(color: Proof.ink.opacity(0.09), radius: 22, y: 14)
                    .overlay(CropMarks())
            }
        }
        .padding(40)
    }

    private func title(_ text: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(text).font(.serif(42, .regular)).foregroundStyle(Proof.ink).fixedSize(horizontal: false, vertical: true)
            Text(body).font(.serif(17)).foregroundStyle(Proof.ink.opacity(0.62)).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 30)
    }

    private func row<Mark: View>(on: Bool, enabled: Bool = true, @ViewBuilder mark: () -> Mark, label: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                mark().frame(width: 16)
                VStack(alignment: .leading, spacing: 3) {
                    Text(label).font(.system(size: 14, weight: on ? .semibold : .regular)).foregroundStyle(Proof.ink)
                    Text(detail).font(.system(size: 11.5)).foregroundStyle(Proof.ink.opacity(0.5)).lineLimit(1)
                }
                Spacer()
                if on {
                    Text("✓").font(.serif(17, .semibold)).foregroundStyle(Proof.pencil)
                }
            }
            .padding(.vertical, 13)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) { Rectangle().fill(Proof.ink.opacity(0.12)).frame(height: 0.75) }
        }
        .buttonStyle(Press())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }

    private func radio(_ on: Bool) -> some View {
        Circle().strokeBorder(on ? Proof.pencil : Proof.ink.opacity(0.35), lineWidth: 1.25)
            .background(Circle().fill(on ? Proof.pencil : .clear).padding(3.5))
            .frame(width: 15, height: 15)
    }

    private var folder: some View {
        VStack(alignment: .leading, spacing: 0) {
            title("Where do you write?", "Quill edits plain Markdown files where they already live. Nothing is copied or uploaded.")
            VStack(spacing: 0) {
                Rectangle().fill(Proof.ink.opacity(0.12)).frame(height: 0.75)
                ForEach(run.places) { place in
                    let on = run.chosen == place.url
                    row(on: on, mark: { radio(on) }, label: place.label,
                        detail: place.detail + (run.census[place.url].map { $0.notes > 0 ? " · \($0.notes) notes" : "" } ?? "")) {
                        withAnimation(.easeOut(duration: 0.18)) { run.chosen = place.url }
                    }
                }
            }
            HStack(spacing: 22) {
                Primary(label: "Continue") {
                    ws.switchVault(run.chosen)
                    go(.voice)
                }
                Button("Choose another folder…") { choose() }
                    .buttonStyle(.plain).font(.system(size: 13)).foregroundStyle(Proof.ink.opacity(0.6))
            }
            .padding(.top, 30)
        }
    }

    private var folderPage: some View {
        let c = run.census[run.chosen]
        return VStack(alignment: .leading, spacing: 9) {
            Text(run.places.first { $0.url == run.chosen }?.label ?? run.chosen.lastPathComponent)
                .font(.serif(24, .semibold)).foregroundStyle(Proof.ink)
            if let c, c.notes > 0 {
                Text("\(c.notes) notes · \(c.words < 1000 ? "\(c.words)" : "about \((c.words / 1000 * 1000).formatted())") words")
                    .font(.system(size: 11.5)).foregroundStyle(Proof.ink.opacity(0.5))
                    .padding(.bottom, 10)
                ForEach(Array(c.titles.enumerated()), id: \.offset) { i, t in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(String(format: "%02d", i + 1)).font(.system(size: 10, design: .monospaced)).foregroundStyle(Proof.ink.opacity(0.35))
                        Text(t).font(.serif(16)).foregroundStyle(Proof.ink.opacity(1 - Double(i) * 0.08)).lineLimit(1)
                    }
                    .transition(.opacity.combined(with: .offset(y: 6)))
                }
            } else {
                Text("An empty folder. Quill adds a first note to start from.").font(.serif(16).italic()).foregroundStyle(Proof.ink.opacity(0.55))
            }
            Spacer()
        }
        .padding(30)
        .animation(.easeOut(duration: 0.3), value: run.chosen)
    }

    private var voice: some View {
        VStack(alignment: .leading, spacing: 0) {
            title("Let Quill read how you write.", "It measures your sentences, punctuation, and habits, and keeps them in Voice.md, a note you can read and edit. The reading happens on this Mac.")
            if run.read {
                Primary(label: "Continue") { go(.cowriter) }
            } else {
                HStack(spacing: 22) {
                    Primary(label: run.reading ? "Reading…" : "Read my notes") { readNotes() }
                        .disabled(run.reading)
                    Button("Not now") { go(.cowriter) }
                        .buttonStyle(.plain).font(.system(size: 13)).foregroundStyle(Proof.ink.opacity(0.6))
                }
            }
        }
    }

    private var voicePage: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("My voice").font(.serif(24, .semibold)).foregroundStyle(Proof.ink)
            if run.lines.isEmpty {
                Text(run.reading ? "Reading your notes…" : "Your measurements will appear here.")
                    .font(.serif(15).italic()).foregroundStyle(Proof.ink.opacity(0.5))
            }
            ForEach(Array(run.lines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("¶").font(.serif(13)).foregroundStyle(Proof.pencil)
                    Text(line).font(.serif(14)).foregroundStyle(Proof.ink).lineSpacing(1).fixedSize(horizontal: false, vertical: true)
                }
                .transition(.opacity.combined(with: .offset(y: 8)))
            }
            Spacer()
        }
        .padding(30)
    }

    private var cowriter: some View {
        VStack(alignment: .leading, spacing: 0) {
            title("Pick your co-writer.", "Quill signs in through the tool itself, so the subscription you already pay for works.")
            VStack(spacing: 0) {
                Rectangle().fill(Proof.ink.opacity(0.12)).frame(height: 0.75)
                ForEach(AgentSpec.all.filter { $0.requires != nil || ws.hasKey }) { spec in
                    let ready = ws.available(spec)
                    let on = ws.agentID == spec.id
                    row(on: on, enabled: ready != false, mark: {
                        Circle().fill(ready == true ? Color.greenInk : Proof.ink.opacity(ready == false ? 0.2 : 0.4)).frame(width: 7, height: 7)
                    }, label: spec.name, detail: ready == false ? (spec.requires == "npx" ? "Needs Node" : "Not installed") : spec.detail) {
                        ws.agentID = spec.id
                    }
                }
            }
            Primary(label: "Show me") { done(ws.agentID) }
                .padding(.top, 30)
        }
        .onAppear { ws.checkAgents() }
    }

    private var cowriterPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your first edit").font(.serif(24, .semibold)).foregroundStyle(Proof.ink)
            Text("Quill opens one of your own sentences. Press ⌘↩, or hold the right ⌥ key and say what you’d change.")
                .font(.serif(16)).foregroundStyle(Proof.ink).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Text("old words").strikethrough(color: Color.redInk).foregroundStyle(Color.redInk)
                Text("your words").foregroundStyle(Proof.ink).underline(color: Color.greenInk)
            }
            .font(.serif(16))
            .padding(.vertical, 6)
            Text("One ⌘Z takes the whole edit back.").font(.system(size: 12)).foregroundStyle(Proof.ink.opacity(0.5))
            Spacer()
        }
        .padding(30)
    }

    private func go(_ step: Firstrunner.Step) {
        withAnimation(still ? nil : Proof.ease) { run.step = step }
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
            let f = await ws.measure()
            let found = describe(f)
            let lines = found.isEmpty ? ["Not enough writing here yet. Quill will learn from your edits instead."] : found
            for line in lines {
                withAnimation(still ? nil : Proof.ease) { run.lines.append(line) }
                try? await Task.sleep(for: .milliseconds(still ? 0 : 420))
            }
            run.reading = false
            run.read = true
        }
    }

    private func done(_ agent: String?) {
        let folders = ws.voiceSources
        Task {
            let picked = await Task.detached { Firstrun.sentence(in: folders) }.value
            finish(picked.map { (sentence: $0.0, source: $0.1) })
        }
    }
}
