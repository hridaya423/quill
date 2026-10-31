import AppKit
import QuillCore

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

    static let paper = color(0xFBFAF7, 0x161615)
    static let ink = color(0x22211F, 0xE8E6E1)
    static let soft = color(0x75716A, 0x9C988F)
    static let faint = color(0xBDB8AE, 0x52504B)
    static let accent = color(0x3D5BD9, 0x8FA6FF)
    static let red = color(0xDC3E42, 0xFF6B6E)
    static let green = color(0x2B9A66, 0x4CC38A)
    static let wash = color(0xF1EFEA, 0x222220)

    static let size: CGFloat = 18
    static let column: CGFloat = 640

    static func serif(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
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
    static let mono = NSFont.monospacedSystemFont(ofSize: size - 3.5, weight: .regular)
    static let hidden = NSFont.systemFont(ofSize: 0.01)

    static func paragraph(lineHeight: CGFloat, before: CGFloat = 0, after: CGFloat = 0, indent: CGFloat = 0) -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.minimumLineHeight = lineHeight
        p.maximumLineHeight = lineHeight
        p.paragraphSpacingBefore = before
        p.paragraphSpacing = after
        p.firstLineHeadIndent = indent
        p.headIndent = indent
        return p
    }

    static let bodyParagraph = paragraph(lineHeight: 30)
    static let gap = paragraph(lineHeight: 16)

    static var bodyAttributes: [NSAttributedString.Key: Any] {
        [.font: body, .foregroundColor: ink, .paragraphStyle: bodyParagraph, .baselineOffset: 0]
    }

    static func headingFont(_ level: Int) -> NSFont {
        switch level {
        case 1: serif(32, .semibold)
        case 2: serif(25, .semibold)
        case 3: serif(21, .semibold)
        default: serif(size, .semibold)
        }
    }
}

@MainActor
final class QuillTextView: NSTextView {
    var onEdit: (() -> Void)?
    var beforeKey: (() -> Void)?
    var gutter = false {
        didSet { if gutter != oldValue { setFrameSize(frame.size) } }
    }
    private var activeLines = NSRange(location: 0, length: 0)
    private var pending: NSRange?
    let fx = CALayer()

    static func make() -> (NSScrollView, QuillTextView) {
        let storage = NSTextContentStorage()
        let layout = NSTextLayoutManager()
        storage.addTextLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.textContainer = container

        let view = QuillTextView(frame: .zero, textContainer: container)
        view.configure()

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        scroll.backgroundColor = Theme.paper
        scroll.scrollerStyle = .overlay
        scroll.documentView = view
        scroll.contentView.postsBoundsChangedNotifications = true
        return (scroll, view)
    }

    private func configure() {
        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = [.width]
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        isRichText = false
        importsGraphics = false
        allowsUndo = true
        usesFindBar = true
        isIncrementalSearchingEnabled = true
        smartInsertDeleteEnabled = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isContinuousSpellCheckingEnabled = true
        isGrammarCheckingEnabled = false
        drawsBackground = true
        backgroundColor = Theme.paper
        insertionPointColor = Theme.accent
        textColor = Theme.ink
        font = Theme.body
        defaultParagraphStyle = Theme.bodyParagraph
        typingAttributes = Theme.bodyAttributes
        selectedTextAttributes = [.backgroundColor: Theme.accent.withAlphaComponent(0.16)]
        linkTextAttributes = [:]
        textContainer?.lineFragmentPadding = 0
        wantsLayer = true
        fx.zPosition = 100
        layer?.addSublayer(fx)
        textStorage?.delegate = self
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        let side = max(36, (newSize.width - Theme.column - (gutter ? 280 : 0)) / 2)
        if abs(textContainerInset.width - side) > 0.5 {
            textContainerInset = NSSize(width: side, height: 72)
            textContainer?.size = NSSize(width: min(Theme.column, newSize.width - side * 2), height: CGFloat.greatestFiniteMagnitude)
        }
        fx.frame = bounds
    }

    override func keyDown(with event: NSEvent) {
        beforeKey?()
        super.keyDown(with: event)
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        beforeKey?()
        super.insertText(string, replacementRange: replacementRange)
    }

    var text: String {
        get { string }
        set {
            string = newValue
            pending = nil
            restyle(NSRange(location: 0, length: (string as NSString).length))
            undoManager?.removeAllActions()
        }
    }

    func textRange(_ r: NSRange) -> NSTextRange? {
        guard let tcs = textContentStorage,
              let start = tcs.location(tcs.documentRange.location, offsetBy: r.location),
              let end = tcs.location(start, offsetBy: r.length)
        else { return nil }
        return NSTextRange(location: start, end: end)
    }

    func segments(_ r: NSRange) -> [CGRect] {
        guard let tlm = textLayoutManager, let tr = textRange(r) else { return [] }
        tlm.ensureLayout(for: tr)
        var rects: [CGRect] = []
        let origin = textContainerOrigin
        tlm.enumerateTextSegments(in: tr, type: .standard, options: r.length == 0 ? [.rangeNotRequired] : []) { _, frame, _, _ in
            rects.append(frame.offsetBy(dx: origin.x, dy: origin.y))
            return true
        }
        return rects
    }

    func render(_ key: NSAttributedString.Key, _ value: Any?, _ r: NSRange) {
        guard let tlm = textLayoutManager, let tr = textRange(r) else { return }
        if let value {
            tlm.addRenderingAttribute(key, value: value, for: tr)
        } else {
            tlm.removeRenderingAttribute(key, for: tr)
        }
    }

    func replace(_ r: NSRange, with s: String) {
        guard let storage = textStorage else { return }
        storage.beginEditing()
        storage.replaceCharacters(in: r, with: NSAttributedString(string: s, attributes: Theme.bodyAttributes))
        storage.endEditing()
        flush()
    }

    override func didChangeText() {
        flush()
        super.didChangeText()
    }

    private func flush() {
        guard let r = pending else { return }
        pending = nil
        let text = string as NSString
        let clamped = NSIntersectionRange(r, NSRange(location: 0, length: text.length))
        let lines = text.lineRange(for: NSRange(location: clamped.location, length: clamped.length))
        restyle(text.substring(with: lines).contains("```") ? NSRange(location: 0, length: text.length) : lines)
        onEdit?()
    }

    func restyle(_ range: NSRange) {
        guard let storage = textStorage else { return }
        let text = storage.string as NSString
        let lines = text.lineRange(for: range)
        var inFence = fenceState(before: lines.location, in: text)
        storage.beginEditing()
        var cursor = lines.location
        repeat {
            let full = text.lineRange(for: NSRange(location: cursor, length: 0))
            var body = full
            while body.length > 0, let c = Unicode.Scalar(text.character(at: NSMaxRange(body) - 1)), CharacterSet.newlines.contains(c) {
                body.length -= 1
            }
            let fenceLine = isFenceLine(text, body)
            let m = markup(text, line: body, inFence: inFence)
            if fenceLine { inFence.toggle() }
            apply(m, full: full, active: NSIntersectionRange(full, activeLines).length > 0 || NSLocationInRange(activeLines.location, full), storage: storage)
            cursor = NSMaxRange(full)
        } while cursor < NSMaxRange(lines)
        storage.endEditing()
    }

    private func apply(_ m: Markup, full: NSRange, active: Bool, storage: NSTextStorage) {
        storage.setAttributes(Theme.bodyAttributes, range: full)
        if m.spans.isEmpty, (storage.string as NSString).substring(with: full).allSatisfy(\.isNewline) {
            storage.addAttribute(.paragraphStyle, value: Theme.gap, range: full)
            return
        }
        for span in m.spans {
            let r = span.range
            switch span.style {
            case .heading(let level):
                let font = Theme.headingFont(level)
                storage.addAttributes([
                    .font: font,
                    .paragraphStyle: Theme.paragraph(lineHeight: ceil(font.pointSize * 1.3), before: level == 1 ? 0 : 10, after: 4),
                ], range: full)
            case .bold:
                storage.addAttribute(.font, value: Theme.bold(storage.attribute(.font, at: r.location, effectiveRange: nil) as? NSFont ?? Theme.body), range: r)
            case .italic:
                storage.addAttribute(.font, value: Theme.italic(storage.attribute(.font, at: r.location, effectiveRange: nil) as? NSFont ?? Theme.body), range: r)
            case .code:
                storage.addAttributes([.font: Theme.mono, .backgroundColor: Theme.wash], range: r)
            case .codeBlock:
                storage.addAttributes([.font: Theme.mono, .foregroundColor: Theme.soft, .paragraphStyle: Theme.paragraph(lineHeight: 24, indent: 0)], range: full)
            case .link:
                storage.addAttributes([.foregroundColor: Theme.accent, .underlineStyle: NSUnderlineStyle.single.rawValue, .underlineColor: Theme.accent.withAlphaComponent(0.35)], range: r)
            case .quote:
                storage.addAttributes([
                    .font: Theme.italic(Theme.body), .foregroundColor: Theme.soft,
                    .paragraphStyle: Theme.paragraph(lineHeight: 30, indent: 22),
                ], range: full)
            case .list:
                storage.addAttributes([.foregroundColor: Theme.accent], range: r)
                storage.addAttribute(.paragraphStyle, value: Theme.paragraph(lineHeight: 30, after: 2, indent: 0), range: full)
            case .strike:
                storage.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: Theme.soft], range: r)
            case .rule:
                storage.addAttributes([.foregroundColor: Theme.faint, .kern: 6], range: full)
            }
        }
        for marker in m.markers where marker.length > 0 {
            if active {
                storage.addAttribute(.foregroundColor, value: Theme.faint, range: marker)
            } else {
                storage.addAttributes([.font: Theme.hidden, .foregroundColor: NSColor.clear], range: marker)
            }
        }
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        let text = string as NSString
        let sel = selectedRange()
        guard NSMaxRange(sel) <= text.length else { return }
        let lines = text.lineRange(for: sel)
        if lines != activeLines {
            let old = activeLines
            activeLines = lines
            if NSMaxRange(old) <= text.length { restyle(old) }
            restyle(lines)
        }
    }
}

extension QuillTextView: NSTextStorageDelegate {
    nonisolated func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters) else { return }
        MainActor.assumeIsolated {
            pending = pending.map { NSUnionRange($0, editedRange) } ?? editedRange
        }
    }
}
