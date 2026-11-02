import AppKit
import SwiftUI

enum Brand {
    static let sky = Color(red: 183 / 255.0, green: 214 / 255.0, blue: 244 / 255.0)
    static let blue = Color(red: 57 / 255.0, green: 104 / 255.0, blue: 153 / 255.0)
    static let cloud = Color(red: 248 / 255.0, green: 250 / 255.0, blue: 252 / 255.0)
    static let night = Color(red: 9 / 255.0, green: 16 / 255.0, blue: 25 / 255.0)
    static let ink = Color(red: 20 / 255.0, green: 33 / 255.0, blue: 47 / 255.0)
    static let slate = Color(red: 76 / 255.0, green: 95 / 255.0, blue: 115 / 255.0)
    static let soft = cloud.opacity(0.68)
    static let faint = cloud.opacity(0.4)
    static let rule = cloud.opacity(0.12)
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

    static func display(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

struct QuillMark: View, Animatable {
    var progress: Double = 1
    var ink: Color = Brand.blue
    var frame: CGRect?
    var outline = QuillMark.outline

    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    struct Shape: Decodable {
        var path: String
        var q: String
        var uill: String
        var wordmark: String
    }

    static let shape: Shape? = Brand.url("mark.json")
        .flatMap { try? Data(contentsOf: $0) }
        .flatMap { try? JSONDecoder().decode(Shape.self, from: $0) }
    static let outline = shape.map { path($0.path) } ?? Path()
    static let lettering = shape.map { path($0.wordmark) } ?? Path()
    static let uill = shape.map { path($0.uill) } ?? Path()
    static let capital = shape.map { path($0.q) } ?? Path()

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

    static func ratio(_ path: Path) -> CGFloat {
        let b = path.boundingRect
        return b.height > 0 ? b.width / b.height : 1
    }

    var body: some View {
        let fill = min(1, max(0, (progress - 0.62) / 0.38))
        ZStack {
            BrandShape(outline: outline, frame: frame)
                .trim(from: 0, to: min(1, progress / 0.8))
                .stroke(ink, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                .opacity(1 - fill)
            BrandShape(outline: outline, frame: frame)
                .fill(ink, style: FillStyle(eoFill: true))
                .opacity(fill)
        }
        .aspectRatio(frame.map { $0.width / $0.height } ?? Self.ratio(outline), contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Quill")
    }
}

struct QuillWordmark: View {
    var ink: Color = Brand.blue

    var body: some View {
        BrandShape(outline: QuillMark.lettering)
            .fill(ink, style: FillStyle(eoFill: true))
            .aspectRatio(QuillMark.ratio(QuillMark.lettering), contentMode: .fit)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Quill")
    }
}

struct BrandShape: SwiftUI.Shape {
    var outline: Path
    var frame: CGRect?

    func path(in rect: CGRect) -> Path {
        let bounds = frame ?? outline.boundingRect
        let scale = min(rect.width / bounds.width, rect.height / bounds.height)
        let transform = CGAffineTransform(translationX: rect.midX - bounds.midX * scale, y: rect.midY - bounds.midY * scale)
            .scaledBy(x: scale, y: scale)
        return outline.applying(transform)
    }
}

struct Primary: View {
    var label: String
    var fill: Color = .accentInk
    var text: Color = Color(nsColor: Theme.onAccent)
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(label)
                    .font(Brand.display(14, .semibold))
                Text("↩")
                    .font(.system(size: 11, weight: .semibold))
                    .opacity(0.55)
            }
            .foregroundStyle(text)
            .padding(.horizontal, 20)
            .frame(height: 38)
            .background(Capsule().fill(fill))
        }
        .buttonStyle(Press())
        .keyboardShortcut(.defaultAction)
    }
}
