import AppKit
import SwiftUI
import QuillCore

struct Place: Identifiable, Hashable {
    var url: URL
    var label: String
    var detail: String
    var id: URL { url }
}

struct Census: Equatable {
    var notes: Int
    var words: Int
}

enum Firstrun {
    static let hedges = ["basically", "kind of", "sort of", "really", "just", "maybe", "pretty", "i think", "quite", "very", "probably", "actually"]

    nonisolated static func diary(_ f: URL) -> Bool {
        f.path.firstMatch(of: /(?i)\/(journal|daily|diary|daily notes|logs?)\//) != nil
            || f.lastPathComponent.firstMatch(of: /^\d{2,4}[-.]\d{2}[-.]\d{2,4}/) != nil
    }

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

    nonisolated static func census(_ folder: URL) -> Census {
        let files = (FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey], options: [.skipsHiddenFiles])?
            .compactMap { $0 as? URL } ?? [])
            .filter { $0.pathExtension.lowercased() == "md" && !$0.lastPathComponent.contains("excalidraw") }
        let bytes = files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        return Census(notes: files.count, words: bytes / 6)
    }

    nonisolated static func sentence(in folders: [URL]) -> (String, String)? {
        var best: (score: Int, text: String, source: String)?
        for folder in folders {
            let key = URLResourceKey.contentModificationDateKey
            let files = (FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [key], options: [.skipsHiddenFiles])?
                .compactMap { $0 as? URL } ?? [])
                .filter { f in
                    f.pathExtension == "md" && !diary(f) && f.lastPathComponent != "Voice.md" && !f.lastPathComponent.contains("excalidraw")
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
    var census: [URL: Census] = [:]
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
    var centered = true

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
        return CGSize(width: centered ? all.map(\.width).max() ?? 0 : proposal.width ?? 0, height: CGFloat(all.count) * leading)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (r, row) in rows(bounds.width, subviews).enumerated() {
            var x = centered ? bounds.midX - row.width / 2 : bounds.minX
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

extension AnyTransition {
    static var focus: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 14)).combined(with: .modifier(active: Blurred(radius: 10), identity: Blurred(radius: 0))),
            removal: .opacity.combined(with: .offset(y: -10)).combined(with: .modifier(active: Blurred(radius: 8), identity: Blurred(radius: 0)))
        )
    }

    static var lens: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.94)).combined(with: .modifier(active: Blurred(radius: 16), identity: Blurred(radius: 0))),
            removal: .opacity.combined(with: .scale(scale: 1.05)).combined(with: .modifier(active: Blurred(radius: 16), identity: Blurred(radius: 0)))
        )
    }
}

struct Listening: View {
    var color: Color

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3.5) {
                ForEach(0..<5, id: \.self) { i in
                    Capsule()
                        .fill(color)
                        .frame(width: 3.5, height: 4 + 10 * max(0, sin(t * 7 - Double(i) * 0.7)))
                }
            }
            .frame(height: 16)
        }
    }
}

struct Glass: Equatable {
    var start: Date?
    var leave: Date?

    struct Frame {
        var trace = 0.0
        var outline = 0.0
        var reveal = 0.0
        var morph = 0.0
        var letters = 0.0
    }

    func at(_ now: Date) -> Frame {
        guard let start else { return Frame() }
        let t = now.timeIntervalSince(start)
        let gone = leave.map { 1 - Self.curve(0.6, 0, 0.3, 1, now.timeIntervalSince($0) / 0.8) } ?? 1
        let morph = Self.curve(0.77, 0, 0.175, 1, (t - 1.9) / 1.5)
        return Frame(
            trace: Self.curve(0.45, 0, 0.55, 1, t / 1.6),
            outline: (1 - Self.curve(0.4, 0, 0.6, 1, (t - 1.45) / 0.45)) * 0.85 * gone,
            reveal: Self.curve(0.23, 1, 0.32, 1, (t - 0.9) / 0.9) * gone,
            morph: morph,
            letters: max(0, min(1, (morph - 0.08) / 0.72)) * gone
        )
    }

    static func curve(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ t: Double) -> Double {
        let t = max(0, min(1, t))
        guard t > 0, t < 1 else { return t }
        var u = t
        for _ in 0..<8 {
            let x = 3 * (1 - u) * (1 - u) * u * x1 + 3 * (1 - u) * u * u * x2 + u * u * u - t
            let dx = 3 * (1 - u) * (1 - u) * x1 + 6 * (1 - u) * u * (x2 - x1) + 3 * u * u * (1 - x2)
            if abs(dx) < 1e-6 { break }
            u = max(0, min(1, u - x / dx))
        }
        return 3 * (1 - u) * (1 - u) * u * y1 + 3 * (1 - u) * u * u * y2 + u * u * u
    }
}

struct Stage: View, Animatable {
    var dawn: Double
    var drift: Double
    var glass = Glass()
    var now: Date?
    @Environment(\.accessibilityReduceMotion) private var still

    nonisolated var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(dawn, drift) }
        set { dawn = newValue.first; drift = newValue.second }
    }

    static let library: ShaderLibrary? = {
        let bundle = Bundle.main.bundleURL.pathExtension == "app" ? Bundle.main : Bundle.module
        return bundle.url(forResource: "default", withExtension: "metallib").map { ShaderLibrary(url: $0) }
    }()

    static let pad: CGFloat = 0.08

    static let mask: Image? = {
        let tight = QuillMark.lettering.boundingRect
        let bounds = tight.insetBy(dx: -tight.height * pad, dy: -tight.height * pad)
        let width = 2048, height = Int(2048 / bounds.width * bounds.height)
        let scale = CGFloat(width) / bounds.width
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        context.translateBy(x: -bounds.minX, y: -bounds.minY)
        context.setBlendMode(.plusLighter)
        for (path, color) in [(QuillMark.capital, CGColor(red: 1, green: 0, blue: 0, alpha: 1)), (QuillMark.uill, CGColor(red: 0, green: 1, blue: 0, alpha: 1))] {
            context.addPath(path.cgPath)
            context.setFillColor(color)
            context.fillPath(using: .evenOdd)
        }
        return context.makeImage().map { Image(decorative: $0, scale: 1) }
    }()

    static func rects(_ size: CGSize, morph: Double) -> (q: CGRect, u: CGRect) {
        let bounds = QuillMark.lettering.boundingRect
        let aspect = bounds.width / bounds.height
        let mid = (QuillMark.capital.boundingRect.midX - bounds.minX) / bounds.width
        let lockup = min(size.width * 0.46, 560)
        let final = CGRect(x: (size.width - lockup) / 2, y: size.height * 0.42 - lockup / aspect / 2, width: lockup, height: lockup / aspect)
        let tall = size.height * 0.48
        let start = CGRect(x: size.width / 2 - mid * tall * aspect, y: size.height * 0.42 - tall / 2, width: tall * aspect, height: tall)
        let k = CGFloat(morph)
        let q = CGRect(x: start.minX + (final.minX - start.minX) * k, y: start.minY + (final.minY - start.minY) * k,
                       width: start.width + (final.width - start.width) * k, height: start.height + (final.height - start.height) * k)
        return (q, final)
    }

    var body: some View {
        Group {
            if let library = Self.library, let mask = Self.mask {
                TimelineView(.animation(minimumInterval: 1 / 60, paused: still && glass.start == nil)) { context in
                    let date = now ?? context.date
                    let t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600)
                    let frame = glass.at(date)
                    GeometryReader { geo in
                        let r = Self.rects(geo.size, morph: frame.morph)
                        let qPad = r.q.insetBy(dx: -r.q.height * Self.pad, dy: -r.q.height * Self.pad)
                        let uPad = r.u.insetBy(dx: -r.u.height * Self.pad, dy: -r.u.height * Self.pad)
                        ZStack(alignment: .topLeading) {
                            Rectangle()
                                .colorEffect(library.horizon(
                                    .float2(geo.size), .float(t), .float(dawn), .float(drift),
                                    .color(Brand.night), .color(Brand.blue), .color(Brand.sky),
                                    .image(mask),
                                    .float4(qPad.minX, qPad.minY, qPad.width, qPad.height),
                                    .float4(uPad.minX, uPad.minY, uPad.width, uPad.height),
                                    .float(frame.reveal), .float(frame.letters)
                                ))
                            if frame.outline > 0 {
                                BrandShape(outline: QuillMark.capital, frame: QuillMark.lettering.boundingRect)
                                    .trim(from: 0, to: frame.trace)
                                    .stroke(Brand.sky, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                                    .frame(width: r.q.width, height: r.q.height)
                                    .offset(x: r.q.minX, y: r.q.minY)
                                    .opacity(frame.outline)
                                    .shadow(color: Brand.sky.opacity(0.8), radius: 6)
                            }
                        }
                    }
                }
            } else {
                Gradients(dawn: dawn, drift: drift)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct Gradients: View {
    var dawn: Double
    var drift: Double
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let size = max(w * 1.7, h * 1.6)
            let rim = h * (1.08 - 0.26 * dawn)
            let center = UnitPoint(x: 0.5 + drift / w, y: (rim + size / 2) / h)
            let edge = 1 / 1.1
            ZStack {
                Brand.night
                RadialGradient(colors: [Brand.blue.opacity(0.42 * dawn), Brand.blue.opacity(0.12 * dawn), .clear],
                               center: UnitPoint(x: 0.5 + drift / w, y: rim / h), startRadius: 0, endRadius: h * 0.85)
                RadialGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .clear, location: edge - 0.02),
                    .init(color: Brand.sky.opacity(0.6 * dawn), location: edge),
                    .init(color: Brand.blue.opacity(0.22 * dawn), location: edge + 0.025),
                    .init(color: .clear, location: 1),
                ], center: center, startRadius: 0, endRadius: size / 2 * 1.1)
                Circle()
                    .fill(LinearGradient(stops: [
                        .init(color: Brand.sky, location: 0),
                        .init(color: Brand.blue, location: 0.03),
                        .init(color: Color(red: 0.07, green: 0.13, blue: 0.21), location: 0.13),
                        .init(color: Brand.night, location: 0.32),
                    ], startPoint: .top, endPoint: .bottom))
                    .frame(width: size, height: size)
                    .position(x: w / 2 + drift, y: rim + size / 2)
                    .opacity(min(1, dawn * 1.6))
            }
            .frame(width: w, height: h)
            .clipped()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct Lockup: View {
    var written: Double
    var typed: Double
    var ink: Color = Brand.sky

    var body: some View {
        let bounds = QuillMark.lettering.boundingRect
        ZStack {
            QuillMark(progress: written, ink: ink, frame: bounds, outline: QuillMark.capital)
            BrandShape(outline: QuillMark.uill, frame: bounds)
                .fill(ink, style: FillStyle(eoFill: true))
                .opacity(typed)
                .offset(x: (1 - typed) * -18)
                .blur(radius: (1 - typed) * 8)
        }
        .aspectRatio(bounds.width / bounds.height, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Quill")
    }
}

struct Film: View {
    var run: Firstrunner
    var fallback: String
    @Binding var dawn: Double
    @Binding var glass: Glass
    var finish: () -> Void
    @State private var beat = 0
    @State private var written = 0.0
    @State private var shown = 0
    @State private var heard = 0
    @State private var tokens: [Token] = []
    @Environment(\.accessibilityReduceMotion) private var still

    private let ask = "cut the hedges"
    private let size: CGFloat = 44

    var body: some View {
        ZStack {
            if !Self.glassy {
                Lockup(written: written, typed: beat >= 1 ? 1 : 0)
                    .frame(width: 330)
                    .offset(y: -30)
                    .opacity(beat >= 2 ? 0 : 1)
                    .scaleEffect(beat >= 2 ? 0.94 : 1)
                    .blur(radius: beat >= 2 ? 10 : 0)
                    .offset(y: beat >= 2 ? -36 : 0)
            }

            VStack(spacing: 46) {
                Flow(gap: size * 0.26, leading: size * 1.28) {
                    ForEach(visible) { token in
                        Text(spelled(token))
                            .font(Brand.display(size, .medium))
                            .tracking(-0.6)
                            .foregroundStyle(token.hedge && beat >= 4 ? Brand.faint : Brand.cloud)
                            .overlay(alignment: .leading) {
                                if token.hedge {
                                    Capsule()
                                        .fill(Brand.sky)
                                        .frame(height: 3.5)
                                        .scaleEffect(x: beat >= 4 ? 1 : 0, anchor: .leading)
                                        .padding(.horizontal, -4)
                                        .offset(y: size * 0.04)
                                        .shadow(color: Brand.sky.opacity(0.7), radius: 6)
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
            .offset(y: -40)
            .opacity(beat >= 7 ? 0 : 1)
            .scaleEffect(beat >= 7 ? 0.96 : 1)
            .blur(radius: beat >= 7 ? 12 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottomTrailing) {
            Button("Skip intro") { finish() }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Brand.soft)
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
                Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Brand.sky)
                Text("Cut the hedges.").font(Brand.display(17, .medium)).foregroundStyle(Brand.cloud)
                Rectangle().fill(Brand.rule).frame(width: 1, height: 16)
                Text(beat >= 6 ? "Kept" : "Keep")
                    .font(Brand.display(13, .semibold))
                    .foregroundStyle(beat >= 6 ? Brand.sky : Brand.night)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(beat >= 6 ? Brand.sky.opacity(0.14) : Brand.sky))
                    .contentTransition(.opacity)
            } else {
                Listening(color: Brand.sky)
                Text(String(ask.prefix(heard)))
                    .font(Brand.display(17, .medium))
                    .foregroundStyle(Brand.cloud)
                    .frame(minWidth: 150, alignment: .leading)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 48)
        .background(Capsule().fill(Brand.cloud.opacity(0.07)))
        .overlay(Capsule().strokeBorder(Brand.cloud.opacity(0.14), lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 24, y: 12)
        .opacity(beat >= 3 && beat < 7 ? 1 : 0)
        .offset(y: beat >= 3 ? 0 : 14)
        .animation(Brand.ease, value: beat)
    }

    private func at(_ ms: Int) async { try? await Task.sleep(for: .milliseconds(ms)) }

    static var glassy: Bool { Stage.library != nil && Stage.mask != nil }

    private func play() async {
        if still {
            dawn = 0.6
            finish()
            return
        }
        await at(250)
        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 3.2)) { dawn = 1 }
        await at(450)
        if Self.glassy {
            glass = Glass(start: .now)
            await at(3400)
            beat = 1
            await at(1300)
            glass.leave = .now
            await at(300)
        } else {
            withAnimation(.timingCurve(0.45, 0.05, 0.35, 1, duration: 2.0)) { written = 1 }
            await at(1700)
            withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.9)) { beat = 1 }
            await at(1600)
        }
        tokens = Token.split(run.sentence?.text ?? fallback)
        withAnimation(.timingCurve(0.6, 0, 0.3, 1, duration: 0.9)) {
            beat = 2
            dawn = 0.62
        }
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

struct Keyboard: View {
    var key: TalkKey
    var down: Bool
    var level: Float

    private struct Cap: Identifiable {
        var id: String { name + glyph }
        var glyph: String
        var name: String
        var width: CGFloat
        var target = false
    }

    private var caps: [Cap] {
        switch key {
        case .fn:
            [Cap(glyph: "fn", name: "", width: 78, target: true), Cap(glyph: "⌃", name: "control", width: 78),
             Cap(glyph: "⌥", name: "option", width: 78), Cap(glyph: "⌘", name: "command", width: 104), Cap(glyph: "", name: "", width: 300)]
        case .rightOption:
            [Cap(glyph: "", name: "", width: 300), Cap(glyph: "⌘", name: "command", width: 104), Cap(glyph: "⌥", name: "option", width: 78, target: true)]
        case .rightCommand:
            [Cap(glyph: "", name: "", width: 300), Cap(glyph: "⌘", name: "command", width: 104, target: true), Cap(glyph: "⌥", name: "option", width: 78)]
        }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(caps) { cap in keycap(cap) }
            if key != .fn { arrows }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.black.opacity(0.35)))
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .white, location: 0.38), .init(color: .white, location: 0.92), .init(color: .clear, location: 1)],
                             startPoint: key == .fn ? .trailing : .leading, endPoint: key == .fn ? .leading : .trailing))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(key.title)
    }

    private func keycap(_ cap: Cap) -> some View {
        let lit = cap.target
        let pressed = lit && down
        return ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(pressed ? Brand.sky : Color(red: 0.13, green: 0.16, blue: 0.21))
                .offset(y: pressed ? 0 : -3)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.black.opacity(0.55)).offset(y: 1))
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(LinearGradient(colors: [Brand.cloud.opacity(pressed ? 0 : 0.16), .clear], startPoint: .top, endPoint: .bottom), lineWidth: 1)
                .offset(y: pressed ? 0 : -3)
            if lit && !down {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(Brand.sky.opacity(0.9), lineWidth: 1.5)
                    .offset(y: -3)
            }
            VStack(alignment: .trailing, spacing: 0) {
                Text(cap.glyph).font(.system(size: cap.name.isEmpty ? 17 : 15, weight: .regular))
                    .frame(maxWidth: .infinity, alignment: cap.name.isEmpty ? .leading : .trailing)
                Spacer(minLength: 0)
                Text(cap.name).font(.system(size: 11.5, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(pressed ? Brand.night : lit ? Brand.sky : Brand.cloud.opacity(0.55))
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .offset(y: pressed ? 0 : -3)
        }
        .frame(width: cap.width, height: 74)
        .shadow(color: Brand.sky.opacity(lit ? (down ? 0.45 + Double(min(level, 1)) * 0.4 : 0.22) : 0), radius: down ? 26 : 18)
        .animation(.spring(response: 0.22, dampingFraction: 0.7), value: down)
    }

    private var arrows: some View {
        HStack(alignment: .bottom, spacing: 6) {
            arrow("◀")
            VStack(spacing: 4) { arrow("▲"); arrow("▼") }
            arrow("▶")
        }
    }

    private func arrow(_ glyph: String) -> some View {
        Text(glyph).font(.system(size: 9)).foregroundStyle(Brand.cloud.opacity(0.45))
            .frame(width: 50, height: 35)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(red: 0.13, green: 0.16, blue: 0.21)).offset(y: -2)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.55))))
    }
}

struct Paper<Content: View>: View {
    var width: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(26)
            .frame(width: width, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Brand.cloud))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.7), lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 40, y: 26)
            .shadow(color: Brand.sky.opacity(0.12), radius: 50)
    }
}

struct Pitch: View {
    var place: String
    var notes: Int?
    @State private var struck = false
    @Environment(\.accessibilityReduceMotion) private var still

    private static let loop = [("doc.text", "Draft in Docs"), ("bubble.left", "Paste into ChatGPT"), ("doc.on.clipboard", "Copy it back"), ("wand.and.rays", "Fix the slop")]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                Text("No more copy, paste, repeat.").font(Brand.display(13, .medium)).foregroundStyle(Brand.soft)
                HStack(spacing: 6) {
                    ForEach(Array(Self.loop.enumerated()), id: \.offset) { i, step in
                        if i > 0 { Image(systemName: "arrow.right").font(.system(size: 9, weight: .bold)).foregroundStyle(Brand.faint) }
                        Label(step.1, systemImage: step.0)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(Brand.cloud.opacity(struck ? 0.4 : 0.8))
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .background(Capsule().fill(Brand.cloud.opacity(0.06)))
                            .overlay(Capsule().strokeBorder(Brand.cloud.opacity(0.1), lineWidth: 1))
                            .fixedSize()
                    }
                }
                .overlay(alignment: .leading) {
                    Capsule().fill(Brand.sky).frame(height: 2)
                        .shadow(color: Brand.sky.opacity(0.8), radius: 5)
                        .scaleEffect(x: struck ? 1 : 0, anchor: .leading)
                }
            }
            Paper(width: 450) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Write with agents, right in your draft.")
                        .font(Brand.display(21, .semibold)).foregroundStyle(Brand.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    feature("mic.fill", "Say what to change", "Hold a key and talk to your draft. Claude, Codex, or Cursor makes the edit.")
                    feature("text.cursor", "Edits land in place", "Every change is marked in your text. Keep it or undo it.")
                    feature("folder.fill", "Your files stay yours", "Plain Markdown in \(place). Quill learns how you write.")
                }
            }
            .overlay(alignment: .topTrailing) {
                if let notes, notes > 0 {
                    Text(notes == 1 ? "1 note ready" : "\(notes.formatted()) notes ready")
                        .font(Brand.display(12.5, .semibold))
                        .foregroundStyle(Brand.night)
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background(Capsule().fill(Brand.sky))
                        .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
                        .offset(x: 14, y: -14)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(still ? 0 : 700))
            withAnimation(still ? nil : .timingCurve(0.65, 0, 0.35, 1, duration: 0.8)) { struck = true }
        }
    }

    private func feature(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Brand.blue)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Brand.sky.opacity(0.45)))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Brand.display(15, .semibold)).foregroundStyle(Brand.ink)
                Text(detail).font(.system(size: 13)).foregroundStyle(Brand.slate).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct Draft {
    enum Kind { case keep, cut, add }

    static let pieces: [(String, Kind)] = [
        ("Hi Maya,", .keep),
        ("I just wanted to quickly check in and see if it would maybe be possible to push", .cut),
        ("can we move", .add),
        ("the launch review to Friday? The deck needs one more pass.", .keep),
        ("Totally fine if not, no worries either way!", .cut),
    ]
    static let before = pieces.filter { $0.1 != .add }.map(\.0).joined(separator: " ")

    struct Word: Identifiable {
        var id: Int
        var text: String
        var kind: Kind
    }

    static let words: [Word] = pieces.flatMap { piece in piece.0.split(separator: " ").map { (String($0), piece.1) } }
        .enumerated().map { Word(id: $0.offset, text: $0.element.0, kind: $0.element.1) }
}

struct Onboarding: View {
    @Bindable var ws: Workspace
    var run: Firstrunner
    var finish: ((sentence: String, source: String)?) -> Void
    @Environment(\.accessibilityReduceMotion) private var still
    @State private var listener = Listener()
    @State private var monitor: Any?
    @State private var dawn = 0.0
    @State private var glass = Glass()
    @State private var cut = false
    @State private var struck = false
    @Namespace private var modes

    private let sample = "We are basically trying to kind of build a tool that maybe helps people write better, in a way."
    private var steps: [Firstrunner.Step] { run.learn ? [.folder, .voice, .talk, .cowriter] : [.folder, .talk, .cowriter] }
    private var sentence: String { run.sentence?.text ?? sample }

    var body: some View {
        ZStack {
            Stage(dawn: dawn, drift: drift, glass: glass)
                .animation(.timingCurve(0.65, 0, 0.35, 1, duration: 1.1), value: run.step)
            if run.step == .overture {
                Film(run: run, fallback: sample, dawn: $dawn, glass: $glass) { go(.folder) }
                    .transition(.opacity)
            } else {
                setup.transition(.opacity)
            }
        }
        .environment(\.colorScheme, .dark)
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

    private var drift: Double {
        switch run.step {
        case .overture: 0
        case .folder: 220
        case .voice: 120
        case .talk: 0
        case .cowriter: -160
        }
    }

    private var setup: some View {
        GeometryReader { geo in
            let wide = geo.size.width >= 940
            let margin = max(56, geo.size.width * 0.075)
            ZStack(alignment: .topLeading) {
                HStack(alignment: .center, spacing: 0) {
                    left
                        .frame(width: wide ? 390 : geo.size.width - margin * 2, alignment: .leading)
                        .frame(maxHeight: .infinity, alignment: .topLeading)
                        .padding(.top, max(60, geo.size.height * 0.2))
                        .padding(.leading, margin)
                    if wide {
                        hero
                            .id(run.step)
                            .transition(.lens)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.trailing, margin * 0.6)
                            .accessibilityHidden(true)
                    }
                }
                .frame(maxHeight: .infinity)
                .padding(.top, 60)
                .padding(.bottom, 40)
                header.padding(.horizontal, margin).padding(.top, 46)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            Lockup(written: 1, typed: 1, ink: Brand.cloud).frame(height: 22)
            Spacer()
            Button("Skip setup") { done() }
                .buttonStyle(.plain)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Brand.soft)
                .keyboardShortcut(.cancelAction)
        }
    }

    private var progress: some View {
        let at = steps.firstIndex(of: run.step) ?? 0
        return HStack(spacing: 6) {
            ForEach(steps.indices, id: \.self) { i in
                Capsule()
                    .fill(i <= at ? Brand.sky : Brand.cloud.opacity(0.16))
                    .frame(width: i == at ? 28 : 14, height: 4)
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: run.step)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(at + 1) of \(steps.count)")
    }

    private var left: some View {
        VStack(alignment: .leading, spacing: 0) {
            progress.padding(.bottom, 30)
            Group {
                switch run.step {
                case .overture, .folder: folder
                case .voice: voice
                case .talk: talk
                case .cowriter: cowriter
                }
            }
            .id(run.step)
            .transition(.focus)
            HStack(spacing: 22) {
                Primary(label: primaryLabel, fill: Brand.sky, text: Brand.night, action: advance)
                if let back = previous {
                    Button("Back") { go(back) }
                        .buttonStyle(.plain)
                        .font(Brand.display(13.5, .medium))
                        .foregroundStyle(Brand.soft)
                        .keyboardShortcut("[", modifiers: .command)
                }
            }
            .padding(.top, 34)
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
        VStack(alignment: .leading, spacing: 14) {
            Text(text).font(Brand.display(42, .semibold)).tracking(-0.8).foregroundStyle(Brand.cloud)
                .fixedSize(horizontal: false, vertical: true)
            Text(body).font(.system(size: 15)).foregroundStyle(Brand.soft).lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 28)
    }

    private func row<Lead: View>(on: Bool, enabled: Bool = true, @ViewBuilder lead: () -> Lead, label: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                lead().frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(Brand.display(14, .semibold)).foregroundStyle(Brand.cloud)
                    Text(detail).font(.system(size: 12)).foregroundStyle(Brand.soft).lineLimit(1)
                }
                Spacer(minLength: 8)
                ZStack {
                    Circle().strokeBorder(Brand.cloud.opacity(on ? 0 : 0.22), lineWidth: 1.5)
                    Circle().fill(Brand.sky).scaleEffect(on ? 1 : 0.3).opacity(on ? 1 : 0)
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(Brand.night).opacity(on ? 1 : 0)
                }
                .frame(width: 18, height: 18)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Brand.cloud.opacity(on ? 0.08 : 0.03)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(on ? Brand.sky.opacity(0.7) : Brand.cloud.opacity(0.06), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(Press())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: on)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var folder: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading("Where do you write?", "Quill edits the Markdown files in one folder. They stay where they are, readable by any app.")
            VStack(alignment: .leading, spacing: 8) {
                ForEach(run.places.prefix(4)) { place in
                    let notes = run.census[place.url].map { $0.notes > 0 ? "\($0.notes.formatted()) notes · \(place.detail)" : "Empty · \(place.detail)" } ?? "Counting…"
                    row(on: run.chosen == place.url, lead: {
                        Image(systemName: place.detail.hasPrefix("Obsidian") ? "books.vertical" : "folder")
                            .font(.system(size: 14)).foregroundStyle(Brand.sky)
                    }, label: place.label, detail: notes) {
                        run.chosen = place.url
                    }
                }
            }
            HStack(spacing: 20) {
                Button { choose() } label: {
                    Label("Another folder…", systemImage: "plus").font(Brand.display(13, .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Brand.soft)
                Toggle(isOn: Binding(get: { run.learn }, set: { run.learn = $0 })) {
                    Text("Learn my voice").font(Brand.display(13, .medium)).foregroundStyle(Brand.cloud)
                }
                .toggleStyle(.checkbox)
                .tint(Brand.sky)
            }
            .padding(.top, 16)
        }
    }

    private var voice: some View {
        let notes = run.census[run.chosen]?.notes ?? 0
        return heading("This is how you write.", run.reading ? "Reading \(notes.formatted()) notes…" : "Quill read \(notes.formatted()) notes and kept what makes them yours. It sharpens this each time you keep or undo an edit.")
    }

    private var talk: some View {
        let key = Prefs.talkKey
        return VStack(alignment: .leading, spacing: 0) {
            heading("Hold \(key.word) and talk.", "Say the change you want. Let go, and your co-writer makes it.")
            Group {
                if run.deaf {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Quill needs the microphone.").font(Brand.display(14, .medium)).foregroundStyle(Brand.cloud)
                        Button("Open Privacy Settings") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
                        }
                        .buttonStyle(.plain).font(Brand.display(13, .semibold)).foregroundStyle(Brand.sky)
                    }
                } else if run.spoke {
                    Label("Heard you. That is the whole gesture.", systemImage: "checkmark.circle.fill")
                        .font(Brand.display(14, .semibold)).foregroundStyle(Brand.sky)
                } else {
                    Text(run.holding ? "Listening. Let go when you’re done." : "Try it now: press and hold the key.")
                        .font(Brand.display(14, .medium)).foregroundStyle(Brand.cloud)
                        .contentTransition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.2), value: run.holding)
        }
    }

    private var cowriter: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading("Who writes with you?", "Pick who leads. Press + to also ask others; their ideas land in your note too, signed. Quill signs in through each tool, so the plans you already pay for work.")
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(AgentSpec.all.filter { !$0.api || ws.available($0) == true }) { spec in
                        tile(spec)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.never)
            .frame(maxHeight: 186)
            .mask(LinearGradient(stops: [.init(color: .white, location: 0.82), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
            HStack(spacing: 10) {
                if !ws.models.isEmpty {
                    Menu {
                        ForEach(ws.models) { m in Button(m.name) { ws.choose(model: m.id) } }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "cpu").font(.system(size: 12, weight: .medium)).foregroundStyle(Brand.sky)
                            Text(ws.model?.name ?? "Model").font(Brand.display(13.5, .semibold)).foregroundStyle(Brand.cloud).lineLimit(1)
                            Image(systemName: "chevron.up.chevron.down").font(.system(size: 9.5, weight: .bold)).foregroundStyle(Brand.soft)
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 40)
                        .background(Capsule().fill(Brand.cloud.opacity(0.06)))
                        .overlay(Capsule().strokeBorder(Brand.cloud.opacity(0.1), lineWidth: 1))
                        .contentShape(Capsule())
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
                HStack(spacing: 0) {
                    ForEach([(Mode.guided, "Edits in place"), (Mode.notes, "Margin notes")], id: \.1) { mode, label in
                        Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { ws.mode = mode } } label: {
                            Text(label)
                                .font(Brand.display(13, .semibold))
                                .foregroundStyle(ws.mode == mode ? Brand.night : Brand.soft)
                                .padding(.horizontal, 14)
                                .frame(height: 32)
                                .background {
                                    if ws.mode == mode { Capsule().fill(Brand.sky).matchedGeometryEffect(id: "mode", in: modes) }
                                }
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(ws.mode == mode ? .isSelected : [])
                    }
                }
                .padding(4)
                .background(Capsule().fill(Brand.cloud.opacity(0.06)))
                .overlay(Capsule().strokeBorder(Brand.cloud.opacity(0.1), lineWidth: 1))
                .fixedSize()
            }
            .padding(.top, 16)
        }
        .onAppear { ws.checkAgents() }
    }

    private func tile(_ spec: AgentSpec) -> some View {
        let on = ws.agentID == spec.id
        let mate = !on && ws.crew.contains(spec.id)
        let ready = ws.available(spec)
        return Button { ws.agentID = spec.id } label: {
            HStack(spacing: 10) {
                Mark(spec: spec, size: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(spec.name).font(Brand.display(13, .semibold)).foregroundStyle(Brand.cloud).lineLimit(1)
                    Text(ready == false ? "Not installed" : on ? "Leads" : mate ? "Also answers" : spec.detail)
                        .font(.system(size: 11)).foregroundStyle(mate || on ? Brand.sky : Brand.soft).lineLimit(1)
                        .contentTransition(.opacity)
                }
                Spacer(minLength: 30)
            }
            .padding(.horizontal, 12)
            .frame(height: 50)
            .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Brand.cloud.opacity(on ? 0.09 : mate ? 0.06 : 0.035)))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(on ? Brand.sky.opacity(0.75) : mate ? Brand.sky.opacity(0.35) : Brand.cloud.opacity(0.06),
                              style: StrokeStyle(lineWidth: 1, dash: mate ? [4, 3] : [])))
            .contentShape(Rectangle())
        }
        .buttonStyle(Press())
        .overlay(alignment: .trailing) {
            if !on, ready != false {
                Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { ws.toggle(mate: spec.id) } } label: {
                    Image(systemName: mate ? "checkmark" : "plus")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(mate ? Brand.night : Brand.soft)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(mate ? Brand.sky : Brand.cloud.opacity(0.08)))
                        .overlay(Circle().strokeBorder(Brand.cloud.opacity(mate ? 0 : 0.14), lineWidth: 1))
                        .contentShape(Circle())
                }
                .buttonStyle(Press())
                .padding(.trailing, 12)
                .help(mate ? "Stop asking \(spec.name)" : "Also ask \(spec.name)")
                .accessibilityLabel(mate ? "Stop asking \(spec.name)" : "Also ask \(spec.name)")
                .transition(.opacity)
            }
        }
        .disabled(ready == false)
        .opacity(ready == false ? 0.4 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: on)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: mate)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    @ViewBuilder private var hero: some View {
        let census = run.census[run.chosen]
        let place = run.places.first { $0.url == run.chosen }?.label ?? run.chosen.lastPathComponent
        switch run.step {
        case .overture, .folder:
            Pitch(place: place, notes: census?.notes)
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: census?.notes)
        case .voice:
            voiceCard
        case .talk:
            talkHero
        case .cowriter:
            editHero
        }
    }

    private var voiceCard: some View {
        Paper(width: 400) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    QuillMark(ink: Brand.blue).frame(height: 22)
                    Text("Voice").font(Brand.display(20, .semibold)).foregroundStyle(Brand.ink)
                    Spacer()
                    Text("Voice.md").font(.system(size: 11.5, weight: .medium)).foregroundStyle(Brand.slate.opacity(0.75))
                }
                .padding(.bottom, 18)
                if run.lines.isEmpty {
                    Shimmer().frame(height: 120)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(run.lines.prefix(5).enumerated()), id: \.offset) { _, line in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Circle().fill(Brand.blue).frame(width: 5, height: 5).offset(y: -2)
                                Text(line).font(.system(size: 14)).foregroundStyle(Brand.ink).lineSpacing(3)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .transition(.opacity.combined(with: .offset(y: 8)).combined(with: .modifier(active: Blurred(radius: 6), identity: Blurred(radius: 0))))
                        }
                    }
                }
            }
        }
    }

    private var talkHero: some View {
        VStack(spacing: 48) {
            Keyboard(key: Prefs.talkKey, down: run.holding, level: run.level)
                .frame(width: 560)
            HStack(spacing: 12) {
                if run.holding {
                    Listening(color: Brand.sky)
                } else {
                    Image(systemName: run.spoke ? "checkmark" : "mic.fill").font(.system(size: 12, weight: .semibold)).foregroundStyle(Brand.sky)
                }
                Text(run.heard.isEmpty ? (run.holding ? "Listening…" : "Hold \(Prefs.talkKey.label) and say a change") : run.heard)
                    .font(Brand.display(16, .medium))
                    .foregroundStyle(run.heard.isEmpty ? Brand.soft : Brand.cloud)
                    .lineLimit(1)
                    .contentTransition(.opacity)
            }
            .padding(.horizontal, 22)
            .frame(height: 50)
            .frame(minWidth: 320)
            .background(Capsule().fill(Brand.cloud.opacity(0.07)))
            .overlay(Capsule().strokeBorder(Brand.cloud.opacity(0.14), lineWidth: 1))
            .animation(.easeOut(duration: 0.15), value: run.heard)
        }
    }

    private var editHero: some View {
        VStack(alignment: .leading, spacing: 20) {
            Paper(width: 460) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        Image(systemName: "envelope").font(.system(size: 12, weight: .semibold)).foregroundStyle(Brand.blue)
                        Text("Re: launch review").font(Brand.display(17, .semibold)).foregroundStyle(Brand.ink)
                        Spacer()
                        Text("Draft").font(.system(size: 11.5, weight: .medium)).foregroundStyle(Brand.slate.opacity(0.75))
                    }
                    Rectangle().fill(Brand.slate.opacity(0.12)).frame(height: 1)
                    Flow(gap: 5, leading: 26, centered: false) {
                        ForEach(Draft.words.filter { cut ? $0.kind != .cut : $0.kind != .add }) { word in
                            Text(word.text)
                                .font(.system(size: 16))
                                .foregroundStyle(word.kind == .cut ? Brand.slate.opacity(0.6) : word.kind == .add ? Brand.blue : Brand.ink)
                                .overlay(alignment: .leading) {
                                    if word.kind == .cut {
                                        Capsule().fill(Brand.blue).frame(height: 1.5).offset(y: 1)
                                            .scaleEffect(x: struck ? 1 : 0, anchor: .leading)
                                    }
                                }
                                .overlay(alignment: .bottom) {
                                    if word.kind == .add { Capsule().fill(Brand.sky).frame(height: 2).offset(y: 3) }
                                }
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .modifier(active: Blurred(radius: 6), identity: Blurred(radius: 0))),
                                    removal: .opacity.combined(with: .scale(scale: 0.7))
                                ))
                        }
                    }
                }
            }
            HStack(spacing: 12) {
                HStack(spacing: -5) {
                    ForEach([ws.spec] + ws.company) { spec in
                        Mark(spec: spec, size: 11)
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(Brand.night))
                            .overlay(Circle().strokeBorder(Brand.cloud.opacity(0.2), lineWidth: 1))
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.75), value: ws.crew)
                Text("“Make it direct.”").font(Brand.display(15, .medium)).foregroundStyle(Brand.cloud)
                Text(cut ? "Keep ⌘↩" : "Editing…")
                    .font(Brand.display(12.5, .semibold))
                    .foregroundStyle(cut ? Brand.night : Brand.sky)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(cut ? Brand.sky : Brand.sky.opacity(0.14)))
                    .contentTransition(.opacity)
            }
            .padding(.horizontal, 18)
            .frame(height: 46)
            .background(Capsule().fill(Brand.cloud.opacity(0.08)))
            .overlay(Capsule().strokeBorder(Brand.cloud.opacity(0.14), lineWidth: 1))
            .padding(.leading, 30)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: ws.agentID)
            .animation(.easeOut(duration: 0.2), value: cut)
        }
        .task {
            cut = false
            struck = false
            try? await Task.sleep(for: .milliseconds(still ? 0 : 900))
            withAnimation(still ? nil : .timingCurve(0.6, 0, 0.3, 1, duration: 0.5)) { struck = true }
            try? await Task.sleep(for: .milliseconds(still ? 0 : 900))
            withAnimation(still ? nil : .spring(response: 0.55, dampingFraction: 0.86)) { cut = true }
        }
    }

    private func go(_ step: Firstrunner.Step) {
        if glass.start != nil, glass.leave == nil { glass.leave = .now }
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
        finish((sentence: Draft.before, source: "a draft email"))
    }
}

struct Shimmer: View {
    @Environment(\.accessibilityReduceMotion) private var still

    var body: some View {
        TimelineView(.animation(paused: still)) { context in
            let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
            VStack(alignment: .leading, spacing: 14) {
                ForEach([0.92, 0.7, 0.84, 0.55], id: \.self) { f in
                    GeometryReader { g in
                        Capsule()
                            .fill(LinearGradient(colors: [Brand.sky.opacity(0.35), Brand.sky.opacity(0.8), Brand.sky.opacity(0.35)],
                                                 startPoint: UnitPoint(x: t * 2 - 1, y: 0), endPoint: UnitPoint(x: t * 2, y: 0)))
                            .frame(width: g.size.width * f)
                    }
                    .frame(height: 9)
                }
            }
        }
    }
}
