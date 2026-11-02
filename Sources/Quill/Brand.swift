import AppKit
import SwiftUI

enum Brand {
    static let ink = Color(red: 0.106, green: 0.133, blue: 0.208)
    static let sheet = Color(red: 0.137, green: 0.169, blue: 0.251)
    static let paper = Color(red: 0.961, green: 0.941, blue: 0.902)
    static let vermilion = Color(red: 0.878, green: 0.267, blue: 0.169)
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

    struct Shape: Decodable {
        var vane: String
        var nib: String
        var from: [Double]
        var to: [Double]
    }

    static let shape: Shape? = Brand.url("mark.json")
        .flatMap { try? Data(contentsOf: $0) }
        .flatMap { try? JSONDecoder().decode(Shape.self, from: $0) }
    static let vane = shape.map { path($0.vane) } ?? Path()
    static let nib = shape.map { path($0.nib) } ?? Path()
    static let frame = vane.boundingRect.union(nib.boundingRect)

    static func path(_ d: String) -> Path {
        var p = Path()
        var words = d.split(separator: " ").makeIterator()
        func point() -> CGPoint? {
            guard let x = words.next().flatMap({ Double($0) }), let y = words.next().flatMap({ Double($0) }) else { return nil }
            return CGPoint(x: x, y: y)
        }
        while let op = words.next() {
            switch op {
            case "M": if let a = point() { p.move(to: a) }
            case "L": if let a = point() { p.addLine(to: a) }
            case "C": if let a = point(), let b = point(), let c = point() { p.addCurve(to: c, control1: a, control2: b) }
            case "Z": p.closeSubpath()
            default: break
            }
        }
        return p
    }

    var body: some View {
        Canvas { ctx, size in
            guard let s = Self.shape else { return }
            let f = Self.frame
            let scale = min(size.width / f.width, size.height / f.height)
            ctx.translateBy(x: (size.width - f.width * scale) / 2, y: (size.height - f.height * scale) / 2)
            ctx.scaleBy(x: scale, y: scale)
            ctx.translateBy(x: -f.minX, y: -f.minY)
            let a = CGPoint(x: s.from[0], y: s.from[1]), b = CGPoint(x: s.to[0], y: s.to[1])
            let length = hypot(b.x - a.x, b.y - a.y)
            let reveal = min(1, progress / 0.82)
            var drawn = ctx
            drawn.translateBy(x: a.x, y: a.y)
            drawn.rotate(by: .radians(atan2(b.y - a.y, b.x - a.x)))
            drawn.clip(to: Path(CGRect(x: -40, y: -length, width: length * reveal + 40, height: length * 2)))
            drawn.rotate(by: .radians(-atan2(b.y - a.y, b.x - a.x)))
            drawn.translateBy(x: -a.x, y: -a.y)
            drawn.fill(Self.vane, with: .color(ink), style: FillStyle(eoFill: true))
            drawn.fill(Self.nib, with: .color(ink))
            let dip = max(0, (progress - 0.82) / 0.18)
            ctx.fill(Self.nib, with: .color(Brand.vermilion.opacity(progress >= 1 ? 1 : dip)))
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
