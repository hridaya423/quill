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
    enum Step: Int { case overture, folder, setup }
    var step: Step = .overture
    var places: [Place]
    var chosen: URL
    var census: [URL: (notes: Int, words: Int, titles: [String])] = [:]
    var lines: [String] = []
    var reading = false
    var read = false
    var learn = true

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

enum Brand {
    static let vellum = Color(red: 0.933, green: 0.898, blue: 0.827)
    static let sheet = Color(red: 0.965, green: 0.941, blue: 0.894)
    static let ink = Color(red: 0.102, green: 0.086, blue: 0.067)
    static let body = Color(red: 0.29, green: 0.259, blue: 0.216)
    static let muted = Color(red: 0.435, green: 0.396, blue: 0.337)
    static let rubric = Color(red: 0.639, green: 0.231, blue: 0.169)
    static let steel = Color(red: 0.56, green: 0.55, blue: 0.53)
    static let graphite = Color(red: 0.29, green: 0.285, blue: 0.28)
    static let ease = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.6)
    static let family = "EB Garamond"

    static func url(_ name: String) -> URL? {
        if Bundle.main.bundleURL.pathExtension == "app" { return Bundle.main.url(forResource: name, withExtension: nil) }
        return Bundle.module.url(forResource: "Brand/\(name)", withExtension: nil)
    }

    static func register() {
        for name in ["EBGaramond.ttf", "EBGaramond-Italic.ttf"] {
            if let url = url(name) { CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) }
        }
    }

    static func serif(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom(family, size: size).weight(weight)
    }

    @MainActor static func nsSerif(_ size: CGFloat) -> NSFont {
        NSFont(descriptor: NSFontDescriptor(fontAttributes: [.family: family]), size: size) ?? Theme.serif(size)
    }

    static var art: NSImage? { url("bude.jpg").flatMap(NSImage.init(contentsOf:)) }
}

enum Nib {
    static func halves(tip: CGPoint, top: CGFloat, width: CGFloat) -> (left: CGPath, right: CGPath) {
        let height = tip.y - top
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: tip.x + (x - 10) / 20 * width, y: top + (y - 1.2) / 29.8 * height)
        }
        let left = CGMutablePath()
        left.move(to: pt(10, 31))
        left.addCurve(to: pt(3, 12), control1: pt(8.6, 24), control2: pt(3.2, 18.5))
        left.addLine(to: pt(3, 5.5))
        left.addCurve(to: pt(7, 1.2), control1: pt(3, 3), control2: pt(4.6, 1.2))
        left.addLine(to: pt(10, 1.2))
        left.closeSubpath()
        let right = CGMutablePath()
        right.move(to: pt(10, 1.2))
        right.addLine(to: pt(13, 1.2))
        right.addCurve(to: pt(17, 5.5), control1: pt(15.4, 1.2), control2: pt(17, 3))
        right.addLine(to: pt(17, 12))
        right.addCurve(to: pt(10, 31), control1: pt(16.8, 18.5), control2: pt(11.4, 24))
        right.closeSubpath()
        var tilt = CGAffineTransform(translationX: tip.x, y: tip.y).rotated(by: -.pi / 10).translatedBy(x: -tip.x, y: -tip.y)
        return (left.copy(using: &tilt) ?? left, right.copy(using: &tilt) ?? right)
    }
}

struct Wordmark: View {
    var size: CGFloat = 30
    var ink: Color = Brand.ink

    struct Layout {
        var letters: Path
        var light: Path
        var dark: Path
        var bounds: CGRect
        var baseline: CGFloat
    }

    static func layout(_ size: CGFloat) -> Layout {
        let base = CTFontDescriptorCreateWithAttributes([kCTFontFamilyNameAttribute: Brand.family, kCTFontVariationAttribute: [0x7767_6874: 520]] as CFDictionary)
        let font = CTFontCreateWithFontDescriptor(base, size, nil)
        let text = NSAttributedString(string: "Qu\u{131}ll", attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        let line = CTLineCreateWithAttributedString(text)
        let letters = CGMutablePath()
        var boxes: [CGRect] = []
        for run in CTLineGetGlyphRuns(line) as! [CTRun] {
            let n = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: n)
            var points = [CGPoint](repeating: .zero, count: n)
            CTRunGetGlyphs(run, CFRange(location: 0, length: n), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: n), &points)
            for i in 0..<n {
                var t = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: points[i].x, ty: 0)
                guard let g = CTFontCreatePathForGlyph(font, glyphs[i], &t) else { continue }
                letters.addPath(g)
                boxes.append(g.boundingBoxOfPath)
            }
        }
        let stem = boxes[2], ell = boxes[3]
        let width = stem.width * 1.1
        let tip = CGPoint(x: stem.midX, y: stem.minY - size * 0.06)
        let nib = Nib.halves(tip: tip, top: ell.minY - size * 0.14, width: width)
        let bounds = letters.boundingBoxOfPath.union(nib.left.boundingBoxOfPath).union(nib.right.boundingBoxOfPath)
        let shift = CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY)
        return Layout(letters: Path(letters).applying(shift), light: Path(nib.left).applying(shift), dark: Path(nib.right).applying(shift),
                      bounds: bounds.offsetBy(dx: -bounds.minX, dy: -bounds.minY), baseline: -bounds.minY)
    }

    var body: some View {
        let l = Self.layout(size)
        Canvas { ctx, _ in
            ctx.fill(l.letters, with: .color(ink))
            ctx.fill(l.light, with: .color(Brand.steel))
            ctx.fill(l.dark, with: .color(Brand.graphite))
        }
        .frame(width: l.bounds.width, height: l.bounds.height)
        .alignmentGuide(.firstTextBaseline) { _ in l.baseline }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Quill")
    }
}

struct Grain: View {
    var body: some View {
        Canvas { ctx, size in
            var rng = SplitMix(seed: 7)
            let count = Int(size.width * size.height / 70)
            for _ in 0..<count {
                let x = Double(rng.next() % 10_000) / 10_000 * size.width
                let y = Double(rng.next() % 10_000) / 10_000 * size.height
                let dark = rng.next() % 3 != 0
                ctx.fill(Path(CGRect(x: x, y: y, width: 1, height: 1)), with: .color(dark ? Brand.ink.opacity(0.045) : .white.opacity(0.3)))
            }
        }
        .allowsHitTesting(false)
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
            ctx.stroke(p, with: .color(Brand.ink.opacity(0.3)), lineWidth: 0.75)
        }
        .padding(-30)
        .allowsHitTesting(false)
    }
}

struct PenStrike: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX - 6, y: r.midY + 3))
        p.addCurve(to: CGPoint(x: r.maxX + 6, y: r.midY - 3),
                   control1: CGPoint(x: r.minX + r.width * 0.3, y: r.midY),
                   control2: CGPoint(x: r.minX + r.width * 0.65, y: r.midY + 1))
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
    private let cut = "everyone else"
    private let kept = "yourself"

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                art.frame(width: geo.size.width * 0.43)
                panel
            }
        }
        .task { await play() }
    }

    private var art: some View {
        Color.black
            .overlay {
                if let image = Brand.art {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                }
            }
            .clipped()
            .overlay { LinearGradient(colors: [.clear, .black.opacity(0.5)], startPoint: .center, endPoint: .bottom) }
            .overlay(alignment: .bottomLeading) { caption }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Detail of Jean Clouet’s portrait of Guillaume Budé, writing in a book with a quill.")
    }

    private var caption: some View {
            (Text("Jean Clouet, ") + Text("Guillaume Budé").italic() + Text(", about 1536. The Metropolitan Museum of Art."))
                .font(Brand.serif(13))
                .foregroundStyle(Brand.sheet.opacity(0.8))
                .padding(24)
    }

    private var panel: some View {
        let font = Brand.nsSerif(size)
        let cutWidth = Theme.width(cut, font)
        let keptWidth = Theme.width(kept, font)
        return VStack(alignment: .leading, spacing: 0) {
            Wordmark(size: 36)
                .padding(.top, 46)
            Spacer()
            VStack(alignment: .leading, spacing: -size * 0.2) {
                Text("Write like")
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    ZStack(alignment: .bottomLeading) {
                        Text(cut)
                            .foregroundStyle(phase >= 2 ? Brand.muted : Brand.ink)
                            .fixedSize()
                            .overlay {
                                PenStrike()
                                    .trim(from: 0, to: phase >= 2 ? 1 : 0)
                                    .stroke(Brand.rubric, style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
                                    .offset(y: -size * 0.02)
                            }
                            .opacity(phase >= 4 ? 0 : 1)
                        Caret()
                            .trim(from: 0, to: phase >= 3 ? 1 : 0)
                            .stroke(Brand.rubric, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                            .frame(width: size * 0.24, height: size * 0.26)
                            .offset(x: -size * 0.15, y: size * 0.04)
                            .opacity(phase == 3 ? 1 : 0)
                        Text(kept)
                            .font(.custom(Brand.family, size: size).italic())
                            .foregroundStyle(Brand.rubric)
                            .fixedSize()
                            .scaleEffect(0.5, anchor: .bottomLeading)
                            .offset(y: -size * 0.84)
                            .opacity(phase == 3 ? 1 : 0)
                            .mask(alignment: .bottomLeading) {
                                Rectangle().frame(width: phase >= 3 ? keptWidth : 0, height: size * 3)
                            }
                        Text(kept)
                            .fixedSize()
                            .opacity(phase >= 4 ? 1 : 0)
                            .offset(y: phase >= 4 ? 0 : -size * 0.3)
                    }
                    .frame(width: phase >= 4 ? keptWidth : cutWidth, alignment: .leading)
                    Text(".")
                }
            }
            .font(Brand.serif(size))
            .foregroundStyle(Brand.ink)
            .lineSpacing(0)
            .opacity(phase >= 1 ? 1 : 0)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Write like yourself.")
            Text("Quill edits your writing while you watch. It learns your voice from your notes and from the edits you keep.")
                .font(Brand.serif(23))
                .foregroundStyle(Brand.body)
                .lineSpacing(6)
                .frame(maxWidth: 500, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 32)
                .opacity(phase >= 1 ? 1 : 0)
            Primary(label: "Begin", action: begin)
                .padding(.top, 40)
                .opacity(phase >= 1 ? 1 : 0)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 92)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background { ZStack { Brand.vellum; Grain() } }
    }

    private func play() async {
        if still { phase = 5; return }
        let beats: [(Int, Int, Animation)] = [
            (1, 300, .easeOut(duration: 0.8)),
            (2, 1200, .timingCurve(0.6, 0, 0.3, 1, duration: 0.55)),
            (3, 600, .timingCurve(0.3, 0, 0.2, 1, duration: 0.7)),
            (4, 1300, .timingCurve(0.23, 1, 0.32, 1, duration: 0.8)),
            (5, 450, .timingCurve(0.23, 1, 0.32, 1, duration: 0.7)),
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
                Text(label)
                    .font(Brand.serif(19, .medium))
                Text("↩")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 20)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Brand.sheet.opacity(0.12)))
                    .opacity(0.7)
            }
            .foregroundStyle(Brand.sheet)
            .padding(.leading, 24)
            .padding(.trailing, 12)
            .padding(.vertical, 11)
            .background {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Brand.ink)
                    .shadow(color: Brand.ink.opacity(0.18), radius: 1, y: 1)
                    .shadow(color: Brand.ink.opacity(0.12), radius: 12, y: 6)
            }
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


    var body: some View {
        ZStack {
            Brand.vellum.ignoresSafeArea()
            Grain().ignoresSafeArea()
            Group {
                switch run.step {
                case .overture: Overture { go(.folder) }.ignoresSafeArea()
                case .folder: split(1, folder, page: folderPage)
                case .setup: split(2, cowriter, page: cowriterPage)
                }
            }
            .id(run.step)
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .offset(y: 12)).animation(Brand.ease.delay(0.06)),
                removal: .opacity.animation(.easeOut(duration: 0.16))
            ))
            if run.step != .overture {
                VStack {
                    HStack(alignment: .center) {
                        Wordmark(size: 36)
                        Spacer()
                        Button("Skip setup") { done(nil) }
                            .buttonStyle(.plain)
                            .font(Brand.serif(15))
                            .foregroundStyle(Brand.muted)
                            .keyboardShortcut(.cancelAction)
                    }
                    Spacer()
                }
                .padding(.top, 46)
                .padding(.bottom, 34)
                .padding(.horizontal, 48)
            }
        }
        .preferredColorScheme(.light)
        .onAppear { run.count() }
    }

    private func split<L: View, R: View>(_ n: Int, _ left: L, page: R) -> some View {
        HStack(alignment: .center, spacing: 80) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    ForEach(1...2, id: \.self) { i in
                        Rectangle()
                            .fill(i < n ? Brand.ink : i == n ? Brand.rubric : Brand.ink.opacity(0.15))
                            .frame(width: 28, height: 2)
                    }
                }
                .padding(.bottom, 28)
                left
            }
            .frame(width: 470, alignment: .leading)
            VStack(alignment: .leading, spacing: 0) {
                page
                    .frame(width: 380, height: 470, alignment: .topLeading)
                    .background(Brand.sheet)
                    .clipShape(Rectangle())
                    .shadow(color: Brand.ink.opacity(0.10), radius: 0.5, y: 0.5)
                    .shadow(color: Brand.ink.opacity(0.10), radius: 22, y: 14)
                    .overlay(CropMarks())
            }
        }
        .padding(40)
    }

    private func title(_ text: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(text).font(Brand.serif(46)).foregroundStyle(Brand.ink).fixedSize(horizontal: false, vertical: true)
            Text(body).font(Brand.serif(20)).foregroundStyle(Brand.body).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 30)
    }

    private func row<Mark: View>(on: Bool, enabled: Bool = true, @ViewBuilder mark: () -> Mark, label: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                mark().frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(Brand.serif(19, on ? .medium : .regular)).foregroundStyle(Brand.ink)
                    Text(detail).font(Brand.serif(14)).foregroundStyle(Brand.muted).lineLimit(1)
                }
                Spacer()
                if on {
                    Text("✓").font(Brand.serif(19, .semibold)).foregroundStyle(Brand.rubric)
                }
            }
            .padding(.vertical, 9)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) { Rectangle().fill(Brand.ink.opacity(0.14)).frame(height: 0.75) }
        }
        .buttonStyle(Press())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }

    private func radio(_ on: Bool) -> some View {
        Circle().strokeBorder(on ? Brand.rubric : Brand.ink.opacity(0.35), lineWidth: 1.25)
            .background(Circle().fill(on ? Brand.rubric : .clear).padding(3.5))
            .frame(width: 15, height: 15)
    }

    private func rule() -> some View {
        Rectangle().fill(Brand.ink.opacity(0.14)).frame(height: 0.75)
    }

    private var folder: some View {
        VStack(alignment: .leading, spacing: 0) {
            title("Where do you write?", "Quill edits the Markdown files in one folder. The files stay where they are.")
            VStack(spacing: 0) {
                rule()
                ForEach(run.places) { place in
                    let on = run.chosen == place.url
                    row(on: on, mark: { radio(on) }, label: place.label,
                        detail: place.detail + (run.census[place.url].map { $0.notes > 0 ? " · \($0.notes) notes" : "" } ?? "")) {
                        withAnimation(.easeOut(duration: 0.18)) { run.chosen = place.url }
                    }
                }
            }
            Toggle(isOn: Binding(get: { run.learn }, set: { run.learn = $0 })) {
                Text("Learn my voice from these notes. It stays on this Mac, in Voice.md.")
                    .font(Brand.serif(16)).foregroundStyle(Brand.body)
            }
            .toggleStyle(.checkbox)
            .tint(Brand.rubric)
            .padding(.top, 20)
            HStack(spacing: 24) {
                Primary(label: "Continue") {
                    ws.switchVault(run.chosen)
                    if run.learn { readNotes() }
                    go(.setup)
                }
                Button("Choose another folder…") { choose() }
                    .buttonStyle(.plain).font(Brand.serif(16)).foregroundStyle(Brand.muted)
            }
            .padding(.top, 30)
        }
    }

    private var folderPage: some View {
        let c = run.census[run.chosen]
        return VStack(alignment: .leading, spacing: 8) {
            Text(run.places.first { $0.url == run.chosen }?.label ?? run.chosen.lastPathComponent)
                .font(Brand.serif(28, .medium)).foregroundStyle(Brand.ink)
            if let c, c.notes > 0 {
                Text("\(c.notes) notes · \(c.words < 1000 ? "\(c.words)" : "about \((c.words / 1000 * 1000).formatted())") words")
                    .font(Brand.serif(15).italic()).foregroundStyle(Brand.muted)
                    .padding(.bottom, 12)
                ForEach(Array(c.titles.enumerated()), id: \.offset) { i, t in
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        Text("\(i + 1)").font(Brand.serif(13)).foregroundStyle(Brand.rubric).frame(width: 14, alignment: .trailing)
                        Text(t).font(Brand.serif(18)).foregroundStyle(Brand.ink.opacity(1 - Double(i) * 0.08)).lineLimit(1)
                    }
                    .transition(.opacity.combined(with: .offset(y: 6)))
                }
            } else {
                Text("This folder is empty. Quill adds a first note for you.").font(Brand.serif(18).italic()).foregroundStyle(Brand.muted)
            }
            Spacer()
        }
        .padding(32)
        .animation(.easeOut(duration: 0.3), value: run.chosen)
    }

    private var voicePage: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("My voice").font(Brand.serif(28, .medium)).foregroundStyle(Brand.ink)
            if run.lines.isEmpty {
                Text(run.reading ? "Reading your notes." : "Your measurements appear here.")
                    .font(Brand.serif(17).italic()).foregroundStyle(Brand.muted)
            }
            ForEach(Array(run.lines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("¶").font(Brand.serif(15)).foregroundStyle(Brand.rubric)
                    Text(line).font(Brand.serif(16)).foregroundStyle(Brand.ink).lineSpacing(0).fixedSize(horizontal: false, vertical: true)
                }
                .transition(.opacity.combined(with: .offset(y: 8)))
            }
            Spacer()
        }
        .padding(32)
    }

    private var cowriter: some View {
        VStack(alignment: .leading, spacing: 0) {
            title("Choose your co-writer.", "Quill uses the sign-in of the tool you choose, so your current subscription works.")
            VStack(spacing: 0) {
                rule()
                ForEach(AgentSpec.all.filter { $0.kind != .anthropic || ws.hasKey }) { spec in
                    let ready = ws.available(spec)
                    let on = ws.agentID == spec.id
                    row(on: on, enabled: ready != false, mark: {
                        Circle().fill(ready == true ? Color.greenInk : Brand.ink.opacity(ready == false ? 0.2 : 0.4)).frame(width: 7, height: 7)
                    }, label: spec.name, detail: ready == false ? spec.missing : spec.detail) {
                        ws.agentID = spec.id
                    }
                }
            }
            HStack(spacing: 28) {
                if !ws.models.isEmpty {
                    Picker("Model", selection: Binding(get: { ws.model?.id ?? "" }, set: { ws.choose(model: $0) })) {
                        ForEach(ws.models) { m in Text(m.name).tag(m.id) }
                    }
                    .fixedSize()
                } else if ws.available(ws.spec) == true {
                    Text("Loading models…").font(Brand.serif(15).italic()).foregroundStyle(Brand.muted)
                }
                Picker("Answers", selection: $ws.mode) {
                    Text("Edits to review").tag(Mode.guided)
                    Text("Margin notes").tag(Mode.notes)
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            .font(Brand.serif(15))
            .padding(.top, 22)
            Primary(label: "Open my first edit") { done(ws.agentID) }
                .padding(.top, 26)
        }
        .onAppear { ws.checkAgents() }
    }

    private var cowriterPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !run.lines.isEmpty || run.reading {
                Text("My voice").font(Brand.serif(22, .medium)).foregroundStyle(Brand.ink)
                ForEach(Array(run.lines.prefix(4).enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("¶").font(Brand.serif(14)).foregroundStyle(Brand.rubric)
                        Text(line).font(Brand.serif(15)).foregroundStyle(Brand.ink).fixedSize(horizontal: false, vertical: true)
                    }
                    .transition(.opacity.combined(with: .offset(y: 8)))
                }
                if run.reading, run.lines.isEmpty {
                    Text("Reading your notes.").font(Brand.serif(15).italic()).foregroundStyle(Brand.muted)
                }
                Divider().padding(.vertical, 6)
            }
            Text("Your first edit").font(Brand.serif(28, .medium)).foregroundStyle(Brand.ink)
            Text("Quill opens one of your recent sentences on a practice page. Press ⌘↩, or hold \(Prefs.talkKey.label) and say the change. Keep it with ⌘↩ or revert it with ⌘⌫.")
                .font(Brand.serif(18)).foregroundStyle(Brand.ink).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Text("old words").strikethrough(color: Color.redInk).foregroundStyle(Color.redInk)
                Text("your words").foregroundStyle(Brand.ink).underline(color: Color.greenInk)
            }
            .font(Brand.serif(18))
            .padding(.vertical, 4)
            Text("Your notes change only when you keep a change.").font(Brand.serif(15).italic()).foregroundStyle(Brand.muted)
            Spacer()
        }
        .padding(32)
    }

    private func go(_ step: Firstrunner.Step) {
        withAnimation(still ? nil : Brand.ease) { run.step = step }
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
            let lines = found.isEmpty ? ["Quill found too little writing here. It learns from your edits instead."] : found
            for line in lines {
                withAnimation(still ? nil : Brand.ease) { run.lines.append(line) }
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
