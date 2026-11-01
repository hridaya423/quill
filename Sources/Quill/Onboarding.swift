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

struct InkField: View {
    var paper: Bool
    @Environment(\.accessibilityReduceMotion) private var still

    var body: some View {
        TimelineView(.animation(paused: still)) { ctx in
            let t = Float(ctx.date.timeIntervalSinceReferenceDate)
            let w = { (a: Float, s: Float) in 0.5 + 0.18 * sin(t * s + a) }
            MeshGradient(width: 3, height: 3, points: [
                [0, 0], [w(0, 0.21), 0], [1, 0],
                [0, w(1, 0.17)], [w(2, 0.23), w(3, 0.19)], [1, w(4, 0.15)],
                [0, 1], [w(5, 0.2), 1], [1, 1],
            ], colors: paper ? [
                .init(red: 0.98, green: 0.97, blue: 0.95), .init(red: 0.95, green: 0.94, blue: 0.99), .init(red: 0.98, green: 0.96, blue: 0.93),
                .init(red: 0.93, green: 0.94, blue: 1.0), .init(red: 0.99, green: 0.98, blue: 0.96), .init(red: 0.97, green: 0.93, blue: 0.9),
                .init(red: 0.98, green: 0.97, blue: 0.95), .init(red: 0.94, green: 0.95, blue: 1.0), .init(red: 0.98, green: 0.97, blue: 0.95),
            ] : [
                .init(red: 0.04, green: 0.05, blue: 0.1), .init(red: 0.1, green: 0.12, blue: 0.32), .init(red: 0.05, green: 0.05, blue: 0.12),
                .init(red: 0.16, green: 0.2, blue: 0.55), .init(red: 0.3, green: 0.24, blue: 0.62), .init(red: 0.08, green: 0.09, blue: 0.25),
                .init(red: 0.05, green: 0.05, blue: 0.1), .init(red: 0.22, green: 0.15, blue: 0.35), .init(red: 0.04, green: 0.04, blue: 0.08),
            ])
        }
        .ignoresSafeArea()
    }
}

struct Onboarding: View {
    @Bindable var ws: Workspace
    var run: Firstrunner
    var finish: ((sentence: String, source: String)?) -> Void
    @State private var shown = false
    @State private var resolved = false
    @Environment(\.accessibilityReduceMotion) private var still

    private let night = Color(red: 0.94, green: 0.93, blue: 0.9)

    var body: some View {
        ZStack {
            InkField(paper: false)
            Group {
                switch run.step {
                case .overture: overture
                case .folder: split(1, folder, page: folderPage)
                case .voice: split(2, voice, page: voicePage)
                case .cowriter: split(3, cowriter, page: cowriterPage)
                }
            }
            .id(run.step)
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .offset(y: 14)).animation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.5).delay(0.08)),
                removal: .opacity.animation(.easeOut(duration: 0.18))
            ))
            VStack {
                HStack {
                    Spacer()
                    if run.step != .overture {
                        Button("Skip setup") { done(nil) }
                            .buttonStyle(.plain)
                            .font(.system(size: 12))
                            .foregroundStyle(night.opacity(0.55))
                            .keyboardShortcut(.cancelAction)
                    }
                }
                Spacer()
            }
            .padding(.top, 18)
            .padding(.trailing, 22)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            run.count()
            withAnimation(still ? nil : .timingCurve(0.23, 1, 0.32, 1, duration: 1.4).delay(0.3)) { shown = true }
            withAnimation(still ? nil : .timingCurve(0.23, 1, 0.32, 1, duration: 1.2).delay(1.1)) { resolved = true }
        }
    }

    private var overture: some View {
        VStack(spacing: 22) {
            Text("Quill")
                .font(.serif(84, .semibold))
                .foregroundStyle(night)
                .blur(radius: shown ? 0 : 18)
                .opacity(shown ? 1 : 0)
                .scaleEffect(shown ? 1 : 1.06)
                .mask {
                    LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: shown ? 1 : 0), .init(color: .clear, location: shown ? 1.15 : 0.05)],
                                   startPoint: .leading, endPoint: .trailing)
                }
            VStack(spacing: 8) {
                Text("Write like yourself, with help.")
                    .font(.serif(26))
                    .foregroundStyle(night)
                Text("A co-writer that edits in front of you and learns your voice.")
                    .font(.system(size: 14))
                    .foregroundStyle(night.opacity(0.6))
            }
            .blur(radius: resolved ? 0 : 10)
            .opacity(resolved ? 1 : 0)
            Typist(night: night)
                .opacity(resolved ? 1 : 0)
                .padding(.top, 6)
            primary("Begin") { go(.folder) }
                .opacity(resolved ? 1 : 0)
                .padding(.top, 12)
        }
    }

    private func split<L: View, R: View>(_ n: Int, _ left: L, page: R) -> some View {
        HStack(spacing: 56) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .leading) {
                    Capsule().fill(night.opacity(0.1))
                    Capsule()
                        .fill(LinearGradient(colors: [Color(red: 0.55, green: 0.65, blue: 1), Color(red: 0.75, green: 0.6, blue: 1), Color(red: 1, green: 0.75, blue: 0.6)],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: 380 * CGFloat(n) / 3)
                }
                .frame(width: 380, height: 2)
                .padding(.bottom, 22)
                Text("\(n) of 3")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(night.opacity(0.45))
                    .padding(.bottom, 14)
                left
            }
            .frame(width: 380, alignment: .leading)
            page
                .frame(width: 360, height: 460, alignment: .topLeading)
                .background(Color(red: 0.984, green: 0.98, blue: 0.969))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .environment(\.colorScheme, .light)
                .shadow(color: .black.opacity(0.35), radius: 40, y: 20)
        }
        .padding(40)
    }

    private func title(_ text: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text).font(.serif(34, .semibold)).foregroundStyle(night).fixedSize(horizontal: false, vertical: true)
            Text(body).font(.system(size: 14)).foregroundStyle(night.opacity(0.65)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 26)
    }

    private func primary(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(label).font(.system(size: 14, weight: .semibold))
                Text("↩").font(.system(size: 12, weight: .medium)).opacity(0.5)
            }
            .foregroundStyle(Color(red: 0.07, green: 0.08, blue: 0.16))
            .padding(.horizontal, 20)
            .padding(.vertical, 11)
            .background(Capsule().fill(night))
        }
        .buttonStyle(Press())
        .keyboardShortcut(.defaultAction)
    }

    private var folder: some View {
        VStack(alignment: .leading, spacing: 0) {
            title("Where do you write?", "Quill works on plain Markdown files in a folder. Nothing is copied or uploaded.")
            VStack(spacing: 8) {
                ForEach(run.places) { place in
                    let on = run.chosen == place.url
                    Button { run.chosen = place.url } label: {
                        HStack(spacing: 12) {
                            Circle().strokeBorder(night.opacity(on ? 1 : 0.4), lineWidth: 1.5)
                                .background(Circle().fill(on ? night : .clear).padding(4))
                                .frame(width: 16, height: 16)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(place.label).font(.system(size: 13.5, weight: .medium)).foregroundStyle(night)
                                Text(place.detail + (run.census[place.url].map { $0.notes > 0 ? " · \($0.notes) notes" : "" } ?? ""))
                                    .font(.system(size: 11.5)).foregroundStyle(night.opacity(0.5)).lineLimit(1)
                            }
                            Spacer()
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(night.opacity(on ? 0.12 : 0.04)))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(Press())
                }
                Button("Choose another folder…") { choose() }
                    .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(night.opacity(0.6)).padding(.top, 4)
            }
            primary("Continue") {
                ws.switchVault(run.chosen)
                go(.voice)
            }
            .padding(.top, 26)
        }
    }

    private var folderPage: some View {
        let c = run.census[run.chosen]
        return VStack(alignment: .leading, spacing: 10) {
            Text(run.places.first { $0.url == run.chosen }?.label ?? run.chosen.lastPathComponent)
                .font(.serif(22, .semibold)).foregroundStyle(Color.ink)
            if let c, c.notes > 0 {
                Text("\(c.notes) notes · \(c.words < 1000 ? "\(c.words)" : "about \((c.words / 1000 * 1000).formatted())") words").font(.system(size: 12)).foregroundStyle(Color.soft)
                Divider().padding(.vertical, 4)
                ForEach(Array(c.titles.enumerated()), id: \.offset) { i, t in
                    Text(t).font(.serif(16)).foregroundStyle(Color.ink.opacity(1 - Double(i) * 0.09)).lineLimit(1)
                        .transition(.opacity.combined(with: .offset(y: 6)))
                }
            } else {
                Text("An empty folder. Quill adds a welcome note to start.").font(.serif(16)).foregroundStyle(Color.soft)
            }
            Spacer()
        }
        .padding(28)
        .animation(.easeOut(duration: 0.3), value: run.chosen)
    }

    private var voice: some View {
        VStack(alignment: .leading, spacing: 0) {
            title("Let Quill read how you write.", "Quill measures your sentences, punctuation, and habits, then keeps them in a note called Voice.md that you can read and edit. It all stays on this Mac.")
            if run.read {
                primary("Continue") { go(.cowriter) }
            } else {
                HStack(spacing: 14) {
                    primary(run.reading ? "Reading…" : "Read my notes") { readNotes() }
                        .disabled(run.reading)
                    Button("Not now") { go(.cowriter) }
                        .buttonStyle(.plain).font(.system(size: 13)).foregroundStyle(night.opacity(0.6))
                }
            }
        }
    }

    private var voicePage: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("My voice").font(.serif(22, .semibold)).foregroundStyle(Color.ink)
            Text("Voice.md").font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.soft)
            Divider().padding(.vertical, 2)
            if run.lines.isEmpty {
                Text(run.reading ? "Reading your notes…" : "Your measurements will appear here.")
                    .font(.serif(15).italic()).foregroundStyle(Color.soft)
            }
            ForEach(Array(run.lines.enumerated()), id: \.offset) { _, line in
                Text(line).font(.serif(14.5)).foregroundStyle(Color.ink).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity.combined(with: .offset(y: 8)))
            }
            Spacer()
        }
        .padding(28)
    }

    private var cowriter: some View {
        VStack(alignment: .leading, spacing: 0) {
            title("Pick your co-writer.", "Quill uses the tool's own sign-in, so your existing subscription works.")
            VStack(spacing: 8) {
                ForEach(AgentSpec.all.filter { $0.requires != nil || ws.hasKey }) { spec in
                    let ready = ws.available(spec)
                    let on = ws.agentID == spec.id
                    Button { ws.agentID = spec.id } label: {
                        HStack(spacing: 12) {
                            Circle().fill(ready == true ? Color.greenInk : ready == false ? night.opacity(0.25) : night.opacity(0.5))
                                .frame(width: 7, height: 7)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(spec.name).font(.system(size: 13.5, weight: .medium)).foregroundStyle(night)
                                Text(ready == false ? (spec.requires == "npx" ? "Needs Node" : "Not installed") : spec.detail)
                                    .font(.system(size: 11.5)).foregroundStyle(night.opacity(0.5))
                            }
                            Spacer()
                            if on { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(night) }
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(night.opacity(on ? 0.12 : 0.04)))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(Press())
                    .disabled(ready == false)
                    .opacity(ready == false ? 0.5 : 1)
                }
            }
            primary("Show me") { done(ws.agentID) }
                .padding(.top, 26)
        }
        .onAppear { ws.checkAgents() }
    }

    private var cowriterPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Next").font(.serif(22, .semibold)).foregroundStyle(Color.ink)
            Text("Quill opens one of your own sentences. Hold the right ⌥ key and say what you would change, or press ⌘↩.")
                .font(.serif(16)).foregroundStyle(Color.ink).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Text("old words").strikethrough(color: Color.redInk).foregroundStyle(Color.redInk)
                Text("→").foregroundStyle(Color.soft)
                Text("your words").foregroundStyle(Color.ink).underline(color: Color.greenInk)
            }
            .font(.serif(16))
            Text("One ⌘Z takes the whole edit back.").font(.system(size: 12)).foregroundStyle(Color.soft)
            Spacer()
        }
        .padding(28)
    }

    private func go(_ step: Firstrunner.Step) {
        withAnimation(still ? nil : .timingCurve(0.23, 1, 0.32, 1, duration: 0.5)) { run.step = step }
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
                withAnimation(still ? nil : .timingCurve(0.23, 1, 0.32, 1, duration: 0.45)) { run.lines.append(line) }
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

struct Typist: View {
    var night: Color
    @Environment(\.accessibilityReduceMotion) private var still
    private let lines = ["make this sound like me", "cut the throat clearing", "what's weak here?", "shorter, and keep my lowercase"]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.045)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let cycle = 3.2
            let i = Int(t / cycle) % lines.count
            let local = t.truncatingRemainder(dividingBy: cycle)
            let line = lines[i]
            let shown = still ? line.count : min(line.count, Int(local / 0.055))
            let fade = still ? 1 : min(1, max(0, (cycle - local) / 0.35))
            HStack(spacing: 10) {
                Image(systemName: "sparkle").font(.system(size: 12, weight: .medium)).foregroundStyle(Color(red: 0.6, green: 0.68, blue: 1))
                Text(String(line.prefix(shown)))
                    .font(.serif(16))
                    .foregroundStyle(night)
                    .opacity(fade)
                Rectangle().fill(night.opacity(0.7)).frame(width: 1.5, height: 17)
                    .opacity(Int(t * 2) % 2 == 0 || shown < line.count ? 1 : 0)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .frame(width: 360)
            .background(Capsule().fill(night.opacity(0.08)))
            .overlay(Capsule().strokeBorder(night.opacity(0.14), lineWidth: 0.75))
        }
        .accessibilityLabel("Example requests, such as: make this sound like me")
    }
}
