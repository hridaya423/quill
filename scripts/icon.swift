import AppKit
import CoreText

let out = URL(fileURLWithPath: CommandLine.arguments[1])
let fontURL = URL(fileURLWithPath: CommandLine.arguments[2])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil)

let vellum = NSColor(srgbRed: 0.965, green: 0.941, blue: 0.894, alpha: 1)
let shade = NSColor(srgbRed: 0.918, green: 0.88, blue: 0.80, alpha: 1)
let rubric = NSColor(srgbRed: 0.639, green: 0.231, blue: 0.169, alpha: 1)

func outline(_ char: Character, _ font: CTFont) -> CGPath {
    var unichar = UniChar(char.unicodeScalars.first!.value)
    var glyph = CGGlyph()
    CTFontGetGlyphsForCharacters(font, &unichar, &glyph, 1)
    return CTFontCreatePathForGlyph(font, glyph, nil) ?? CGMutablePath()
}

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let ns = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ns
    let ctx = ns.cgContext
    let inset = s * 0.1
    let tile = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let path = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
    shadow.shadowBlurRadius = s * 0.025
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.01)
    shadow.set()
    NSGradient(colors: [vellum, shade])!.draw(in: path, angle: -90)
    NSShadow().set()

    let nibHeight = tile.height * (px <= 32 ? 0.74 : 0.6)
    let width = nibHeight / 1.5
    let tipY = tile.midY - nibHeight / 2 - tile.height * 0.01
    let topY = tipY + nibHeight
    let box = CGRect(x: tile.midX, y: 0, width: 0, height: 0)
    func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: box.midX + (x - 10) / 20 * width, y: topY - (y - 1.2) / 29.8 * nibHeight)
    }
    let nib = CGMutablePath()
    nib.move(to: pt(10, 31))
    nib.addCurve(to: pt(3, 12), control1: pt(8.6, 24), control2: pt(3.2, 18.5))
    nib.addLine(to: pt(3, 5.5))
    nib.addCurve(to: pt(7, 1.2), control1: pt(3, 3), control2: pt(4.6, 1.2))
    nib.addLine(to: pt(13, 1.2))
    nib.addCurve(to: pt(17, 5.5), control1: pt(15.4, 1.2), control2: pt(17, 3))
    nib.addLine(to: pt(17, 12))
    nib.addCurve(to: pt(10, 31), control1: pt(16.8, 18.5), control2: pt(11.4, 24))
    nib.closeSubpath()
    if px > 32 {
        let hole = pt(10, 13.4)
        let r = width * (px >= 256 ? 0.075 : 0.1)
        nib.addEllipse(in: CGRect(x: hole.x - r, y: hole.y - r, width: r * 2, height: r * 2))
        let slit = width * (px >= 256 ? 0.03 : 0.065)
        nib.addRect(CGRect(x: hole.x - slit / 2, y: tipY + nibHeight * 0.06, width: slit, height: hole.y - r - tipY - nibHeight * 0.06 + 0.5))
    }
    ctx.setFillColor(rubric.cgColor)
    ctx.addPath(nib)
    ctx.fillPath(using: .evenOdd)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
                   ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! render(px).write(to: out.appending(path: "icon_\(name).png"))
}
