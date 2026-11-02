import AppKit

@MainActor
enum Theme {
    static func color(_ light: UInt32, _ dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        }
    }

    static let paper = color(0xFAF7F3, 0x191714)
    static let sheet = color(0xF3F0E9, 0x22201D)
    static let ink = color(0x221D18, 0xE9E6DF)
    static let soft = color(0x69625B, 0xB9B5AE)
    static let faint = color(0xC2BDB5, 0x484440)
    static let rule = color(0xE1DDD7, 0x302D2A)
    static let accent = color(0xA83825, 0xF5A083)
    static let red = accent
    static let green = color(0x56805F, 0x86B990)
    static let wash = sheet
    static let mark = color(0xFCE4D9, 0x3D241E)
    static let selection = color(0xE6E0D6, 0x3A3631)

    static let size: CGFloat = 20
    static let column: CGFloat = 620
    static let hang: CGFloat = 48

    static func serif(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        let garamond = NSFontDescriptor(fontAttributes: [.family: "EB Garamond", .traits: [NSFontDescriptor.TraitKey.weight: weight]])
        if let font = NSFont(descriptor: garamond, size: size), font.familyName == "EB Garamond" { return font }
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        return base.fontDescriptor.withDesign(.serif).flatMap { NSFont(descriptor: $0, size: size) } ?? base
    }

    static func italic(_ font: NSFont) -> NSFont {
        NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
    }

    static func bold(_ font: NSFont) -> NSFont {
        NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
    }

    static let body = serif(size)
    static let mono = NSFont.monospacedSystemFont(ofSize: size - 5, weight: .regular)
    static let hidden = NSFont.systemFont(ofSize: 0.01)

    static func paragraph(lineHeight: CGFloat, before: CGFloat = 0, after: CGFloat = 0, indent: CGFloat = 0, hanging: CGFloat = 0) -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.minimumLineHeight = lineHeight
        p.maximumLineHeight = lineHeight
        p.paragraphSpacingBefore = before
        p.paragraphSpacing = after
        p.firstLineHeadIndent = max(0, hang + indent - hanging)
        p.headIndent = hang + indent
        return p
    }

    static func width(_ s: String, _ font: NSFont) -> CGFloat {
        ceil((s as NSString).size(withAttributes: [.font: font]).width)
    }

    static let bodyParagraph = paragraph(lineHeight: 31)
    static let gap = paragraph(lineHeight: 16)

    static var bodyAttributes: [NSAttributedString.Key: Any] {
        [.font: body, .foregroundColor: ink, .paragraphStyle: bodyParagraph, .baselineOffset: 0]
    }

    static let headings = [serif(34, .medium), serif(27, .medium), serif(23, .medium), serif(size, .semibold)]

    static func headingFont(_ level: Int) -> NSFont {
        headings[min(max(level, 1), 4) - 1]
    }
}
