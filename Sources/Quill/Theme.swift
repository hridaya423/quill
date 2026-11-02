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

    static let paper = color(0xF8FAFC, 0x0E1620)
    static let sheet = color(0xEEF3F9, 0x152130)
    static let ink = color(0x14212F, 0xEAF1F8)
    static let soft = color(0x4C5F73, 0xB3C2D2)
    static let faint = color(0x9FB0C2, 0x52657A)
    static let rule = color(0xDCE5EF, 0x233345)
    static let accent = color(0x396899, 0xB7D6F4)
    static let onAccent = color(0xF8FAFC, 0x0E1620)
    static let red = color(0xB3363F, 0xFF9AA2)
    static let green = color(0x2F7356, 0x8FC9AB)
    static let wash = sheet
    static let mark = color(0xE2EEFA, 0x1C2E44)
    static let selection = color(0xCFE3F7, 0x27425F)

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
