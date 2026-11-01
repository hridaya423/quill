import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let inset = s * 0.1
    let tile = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let path = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
    shadow.shadowBlurRadius = s * 0.025
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.01)
    shadow.set()
    NSGradient(colors: [NSColor(srgbRed: 0.995, green: 0.99, blue: 0.975, alpha: 1), NSColor(srgbRed: 0.94, green: 0.925, blue: 0.895, alpha: 1)])!
        .draw(in: path, angle: -90)
    NSShadow().set()
    let size = tile.height * 0.68
    let base = NSFont.systemFont(ofSize: size, weight: .semibold)
    let font = base.fontDescriptor.withDesign(.serif).flatMap { NSFont(descriptor: $0, size: size) } ?? base
    let q = NSAttributedString(string: "Q", attributes: [.font: font, .foregroundColor: NSColor(srgbRed: 0.133, green: 0.129, blue: 0.122, alpha: 1)])
    let b = q.size()
    q.draw(at: NSPoint(x: tile.midX - b.width / 2, y: tile.midY - b.height / 2 + tile.height * 0.03))
    let dot = tile.width * 0.075
    NSColor(srgbRed: 0.24, green: 0.36, blue: 0.85, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: tile.maxX - tile.width * 0.24, y: tile.minY + tile.height * 0.17, width: dot, height: dot)).fill()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
                   ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! render(px).write(to: out.appending(path: "icon_\(name).png"))
}
