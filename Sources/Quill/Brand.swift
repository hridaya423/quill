import AppKit
import SwiftUI

enum Brand {
    static let ink = Color(red: 0.082, green: 0.071, blue: 0.059)
    static let sheet = Color(red: 0.118, green: 0.102, blue: 0.09)
    static let paper = Color(red: 0.957, green: 0.918, blue: 0.859)
    static let ember = Color(red: 1, green: 0.357, blue: 0.212)
    static let soft = paper.opacity(0.62)
    static let faint = paper.opacity(0.36)
    static let rule = paper.opacity(0.1)
    static let ease = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.6)
    static let family = "EB Garamond"

    static func url(_ name: String) -> URL? {
        if Bundle.main.bundleURL.pathExtension == "app" { return Bundle.main.url(forResource: name, withExtension: nil) }
        return Bundle.module.url(forResource: "Brand/\(name)", withExtension: nil)
    }

    static func register() {
        for name in ["EBGaramond.ttf", "EBGaramond-Italic.ttf", "InstrumentSerif.ttf", "InstrumentSerif-Italic.ttf"] {
            if let url = url(name) { CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) }
        }
    }

    static func serif(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom(family, size: size).weight(weight)
    }

    static func display(_ size: CGFloat, italic: Bool = false) -> Font {
        .custom(italic ? "InstrumentSerif-Italic" : "InstrumentSerif-Regular", fixedSize: size)
    }

    static func nsDisplay(_ size: CGFloat, italic: Bool = false) -> NSFont {
        NSFont(name: italic ? "InstrumentSerif-Italic" : "InstrumentSerif-Regular", size: size) ?? .systemFont(ofSize: size)
    }
}

struct QuillMark: View, Animatable {
    var progress: Double = 1
    var ink: Color = Brand.paper

    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    struct Stroke: Decodable {
        var nib: Double
        var angle: Double
        var dip: Double
        var bowl: [[Double]]
        var tail: [[Double]]
    }

    struct Line {
        var points: [CGPoint]
        var widths: [Double]
        var lengths: [Double]
        var total: Double { lengths.last ?? 0 }

        init(_ samples: [[Double]]) {
            points = samples.map { CGPoint(x: $0[0], y: $0[1]) }
            widths = samples.map { $0[2] }
            var run = [0.0]
            for i in points.indices.dropFirst() {
                run.append(run[i - 1] + hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y))
            }
            lengths = run
        }

        func ribbon(from start: Double, to end: Double, nib: Double, angle: Double) -> Path {
            guard end > start else { return Path() }
            let h = CGVector(dx: cos(angle) / 2, dy: -sin(angle) / 2)
            var a: [CGPoint] = [], b: [CGPoint] = []
            func add(_ p: CGPoint, _ w: Double) {
                a.append(CGPoint(x: p.x + h.dx * nib * w, y: p.y + h.dy * nib * w))
                b.append(CGPoint(x: p.x - h.dx * nib * w, y: p.y - h.dy * nib * w))
            }
            for i in points.indices {
                if lengths[i] < start { continue }
                if lengths[i] > end {
                    if i > 0 {
                        let f = (end - lengths[i - 1]) / max(lengths[i] - lengths[i - 1], 0.0001)
                        let p = CGPoint(x: points[i - 1].x + (points[i].x - points[i - 1].x) * f, y: points[i - 1].y + (points[i].y - points[i - 1].y) * f)
                        add(p, widths[i - 1] + (widths[i] - widths[i - 1]) * f)
                    }
                    break
                }
                add(points[i], widths[i])
            }
            var path = Path()
            guard let first = a.first else { return path }
            path.move(to: first)
            for p in a.dropFirst() { path.addLine(to: p) }
            for p in b.reversed() { path.addLine(to: p) }
            path.closeSubpath()
            return path
        }
    }

    static let stroke: Stroke? = Brand.url("mark.json")
        .flatMap { try? Data(contentsOf: $0) }
        .flatMap { try? JSONDecoder().decode(Stroke.self, from: $0) }
    static let bowl = stroke.map { Line($0.bowl) }
    static let tail = stroke.map { Line($0.tail) }
    static let frame: CGRect = {
        guard let s = stroke else { return CGRect(x: 0, y: 0, width: 1024, height: 1024) }
        let all = s.bowl + s.tail
        let pad = s.nib / 2 + 2
        let xs = all.map { $0[0] }, ys = all.map { $0[1] }
        return CGRect(x: xs.min()! - pad, y: ys.min()! - pad, width: xs.max()! - xs.min()! + pad * 2, height: ys.max()! - ys.min()! + pad * 2)
    }()

    var body: some View {
        Canvas { ctx, size in
            guard let s = Self.stroke, let bowl = Self.bowl, let tail = Self.tail else { return }
            let scale = min(size.width / Self.frame.width, size.height / Self.frame.height)
            ctx.translateBy(x: (size.width - Self.frame.width * scale) / 2, y: (size.height - Self.frame.height * scale) / 2)
            ctx.scaleBy(x: scale, y: scale)
            ctx.translateBy(x: -Self.frame.minX, y: -Self.frame.minY)
            let drawn = progress * (bowl.total + tail.total)
            ctx.fill(bowl.ribbon(from: 0, to: min(drawn, bowl.total), nib: s.nib, angle: s.angle), with: .color(ink))
            let t = drawn - bowl.total
            guard t > 0 else { return }
            let dip = tail.total * s.dip
            ctx.fill(tail.ribbon(from: 0, to: min(t, dip + 2), nib: s.nib, angle: s.angle), with: .color(ink))
            ctx.fill(tail.ribbon(from: dip, to: t, nib: s.nib, angle: s.angle), with: .color(Brand.ember))
        }
        .aspectRatio(Self.frame.width / Self.frame.height, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Quill")
    }
}

struct Primary: View {
    var label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(label)
                    .font(.system(size: 13.5, weight: .semibold))
                Text("↩")
                    .font(.system(size: 11, weight: .semibold))
                    .opacity(0.6)
            }
            .foregroundStyle(Color(nsColor: Theme.paper))
            .padding(.horizontal, 18)
            .frame(height: 36)
            .background(Capsule().fill(Color.ink))
            .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
        }
        .buttonStyle(Press())
        .keyboardShortcut(.defaultAction)
    }
}
