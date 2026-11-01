import AppKit
import QuillCore

extension NSAttributedString.Key {
    static let quote = NSAttributedString.Key("QuillQuote")
}

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

    static let paper = color(0xF7F2E8, 0x17140F)
    static let ink = color(0x1F1A14, 0xE9E1D2)
    static let soft = color(0x6F6556, 0xA69C8A)
    static let faint = color(0xBDB3A1, 0x4F473B)
    static let accent = color(0xA33B2B, 0xE07A62)
    static let red = color(0xA33B2B, 0xE07A62)
    static let green = color(0x4E7A5A, 0x7FB08A)
    static let wash = color(0xEFE7D8, 0x231E17)
    static let pending = color(0xF3E3D6, 0x2E1F19)

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

enum EditSource {
    case agent(turn: Int, flags: [String])
    case other
    case restore
}

extension UndoManager.UserInfoKey {
    static let turn = UndoManager.UserInfoKey(rawValue: "QuillTurn")
}

@MainActor
final class QuillTextView: NSTextView {
    var onEdit: (() -> Void)?
    var onUndo: ((String, Bool) -> Void)?
    var onResolve: (([Hunk], Outcome) -> Void)?
    var onReview: (() -> Void)?
    var onCaret: (() -> Void)?
    var onHover: ((Int?) -> Void)?
    var beforeKey: ((NSEvent?) -> Bool)?
    var gutter = false {
        didSet { if gutter != oldValue { setFrameSize(frame.size) } }
    }
    private(set) var review = Review()
    private var activeLines = NSRange(location: 0, length: 0)
    private var pending: [NSRange] = []
    private var crossed: [Hunk] = []
    private var programmatic = false
    private var reviewed = 0
    private var marks: [NSRange: [NSAttributedString.Key: Any]] = [:]
    let fx = CALayer()

    static func make() -> (NSScrollView, QuillTextView) {
        let storage = NSTextContentStorage()
        let layout = NSTextLayoutManager()
        storage.addTextLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = false
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
        let side = max(8, max(36, (newSize.width - Theme.column - (gutter ? 280 : 0)) / 2) - Theme.hang)
        let width = min(Theme.column, newSize.width - 72) + Theme.hang
        if abs(textContainerInset.width - side) > 0.5 || textContainer?.size.width != width {
            textContainerInset = NSSize(width: side, height: (Self.top + Self.bottom) / 2)
            textContainer?.size = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        }
        fx.frame = bounds
    }

    static let top: CGFloat = 72
    static let bottom: CGFloat = 220

    override var textContainerOrigin: NSPoint {
        NSPoint(x: textContainerInset.width, y: Self.top)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.userInfo?["quill"] != nil { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: ["quill": true]))
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let point = convert(event.locationInWindow, from: nil)
        let index = characterIndexForInsertion(at: point)
        let over = review.hunk(at: index).map { h in segments(h.range).contains { $0.insetBy(dx: -2, dy: -2).contains(point) } } ?? false
        onHover?(over ? index : nil)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHover?(nil)
    }

    override func keyDown(with event: NSEvent) {
        if beforeKey?(event) == true { return }
        super.keyDown(with: event)
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        _ = beforeKey?(nil)
        super.insertText(string, replacementRange: replacementRange)
    }

    @objc func undo(_ sender: Any?) { step(back: true) }
    @objc func redo(_ sender: Any?) { step(back: false) }

    private func step(back: Bool) {
        _ = beforeKey?(nil)
        guard let um = undoManager, back ? um.canUndo : um.canRedo else { return }
        func top() -> (String, Int?) {
            back ? (um.undoActionName, um.undoActionUserInfoValue(forKey: .turn) as? Int)
                 : (um.redoActionName, um.redoActionUserInfoValue(forKey: .turn) as? Int)
        }
        let first = top()
        back ? um.undo() : um.redo()
        guard first.0 == "Changes", let turn = first.1 else { return }
        while back ? um.canUndo : um.canRedo, top() == ("Changes", turn) {
            back ? um.undo() : um.redo()
        }
    }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        guard item.action == #selector(undo(_:)) || item.action == #selector(redo(_:)), let um = undoManager else {
            return super.validateUserInterfaceItem(item)
        }
        let back = item.action == #selector(undo(_:))
        (item as? NSMenuItem)?.title = back ? um.undoMenuItemTitle : um.redoMenuItemTitle
        return back ? um.canUndo : um.canRedo
    }

    @objc func bold(_ sender: Any?) { wrap("**") }
    @objc func italic(_ sender: Any?) { wrap("*") }
    @objc func strike(_ sender: Any?) { wrap("~~") }
    @objc func code(_ sender: Any?) { wrap("`") }

    private func wrap(_ marker: String) {
        let text = string as NSString
        let sel = selectedRange()
        let m = (marker as NSString).length
        let outer = NSRange(location: sel.location - m, length: sel.length + 2 * m)
        let doubled = m == 1 && outer.location > 0 && NSMaxRange(outer) < text.length
            && text.substring(with: NSRange(location: outer.location - 1, length: 1)) == marker
            && text.substring(with: NSRange(location: NSMaxRange(outer), length: 1)) == marker
        if !doubled, outer.location >= 0, NSMaxRange(outer) <= text.length,
           text.substring(with: NSRange(location: outer.location, length: m)) == marker,
           text.substring(with: NSRange(location: NSMaxRange(sel), length: m)) == marker {
            let inner = text.substring(with: sel)
            guard shouldChangeText(in: outer, replacementString: inner) else { return }
            replaceCharacters(in: outer, with: inner)
            didChangeText()
            setSelectedRange(NSRange(location: outer.location, length: sel.length))
            return
        }
        let inner = text.substring(with: sel)
        let wrapped = marker + inner + marker
        guard shouldChangeText(in: sel, replacementString: wrapped) else { return }
        replaceCharacters(in: sel, with: wrapped)
        didChangeText()
        setSelectedRange(NSRange(location: sel.location + m, length: sel.length))
    }

    @objc func heading(_ sender: NSMenuItem) {
        let text = string as NSString
        let line = text.lineRange(for: NSRange(location: selectedRange().location, length: 0))
        let body = text.substring(with: line)
        let run = body.prefix { $0 == "#" }.count
        let after = body.dropFirst(run).first
        let hashes = after == nil || after == " " || after == "\n" ? run : 0
        var marker = hashes > 0 ? hashes : 0
        if hashes > 0, body.dropFirst(hashes).first == " " { marker += 1 }
        let existing = NSRange(location: line.location, length: hashes > 0 ? marker : 0)
        let level = sender.tag
        let next = level == 0 || level == hashes ? "" : String(repeating: "#", count: level) + " "
        guard shouldChangeText(in: existing, replacementString: next) else { return }
        let caret = selectedRange()
        replaceCharacters(in: existing, with: next)
        didChangeText()
        let delta = (next as NSString).length - existing.length
        setSelectedRange(NSRange(location: max(line.location + (next as NSString).length, caret.location + delta), length: caret.length))
    }

    var text: String {
        get { string }
        set {
            marks = [:]
            review = Review()
            programmatic = true
            string = newValue
            programmatic = false
            pending = []
            crossed = []
            restyle(NSRange(location: 0, length: (string as NSString).length))
            undoManager?.removeAllActions()
            onReview?()
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

    func mark(_ r: NSRange, _ attributes: [NSAttributedString.Key: Any]?) {
        marks[r] = attributes
        restyle(r)
    }

    func clearMarks(_ key: NSAttributedString.Key) {
        let touched = marks.filter { $0.value[key] != nil }
        guard !touched.isEmpty else { return }
        for (r, _) in touched { marks[r] = nil }
        let len = (string as NSString).length
        for (r, _) in touched where NSMaxRange(r) <= len { restyle(r) }
    }

    func replace(_ r: NSRange, with s: String, by source: EditSource = .other) {
        guard let storage = textStorage else { return }
        marks = marks.filter { NSMaxRange($0.key) <= r.location }
        let before = NSString(string: string)
        programmatic = true
        storage.beginEditing()
        storage.replaceCharacters(in: r, with: NSAttributedString(string: s, attributes: Theme.bodyAttributes))
        storage.endEditing()
        programmatic = false
        let span = review.hunks.map(\.range)
        switch source {
        case .agent(let turn, let flags):
            review.agent(r, before: before, after: NSString(string: string), turn: turn, flags: flags)
        case .other:
            cross(r, length: (s as NSString).length)
        case .restore:
            break
        }
        pending += span + review.hunks.map(\.range)
        flush()
    }

    private func cross(_ r: NSRange, length n: Int) {
        let delta = n - r.length
        crossed += review.user(r, length: n).map { h in
            var h = h
            let lo = min(h.range.location, r.location)
            h.range = NSRange(location: lo, length: max(NSMaxRange(h.range), NSMaxRange(r)) + delta - lo)
            return h
        }
    }

    func setReview(_ next: Review) {
        pending += review.hunks.map(\.range) + next.hunks.map(\.range)
        review = next
        flush()
    }

    func keep(_ hunks: [Hunk]) {
        let before = review
        var next = review
        let gone = hunks.compactMap { next.remove($0.id) }
        guard !gone.isEmpty else { return }
        setReview(next)
        onResolve?(gone.filter { !$0.touched }, .kept)
        onResolve?(gone.filter(\.touched), .rewritten)
        record([], name: gone.count == 1 ? "Keep Change" : "Keep Changes", turn: 0, before: before, after: review, back: true)
    }

    func revert(_ hunks: [Hunk]) {
        let before = review
        var next = review
        let gone = hunks.compactMap { next.remove($0.id) }
        guard !gone.isEmpty else { return }
        setReview(next)
        onResolve?(gone, .reverted)
        let inverse = commit(gone.map { Change(range: $0.range, text: $0.old) }, by: .other)
        record(inverse, name: gone.count == 1 ? "Revert Change" : "Revert Changes", turn: 0, before: before, after: review, back: true)
    }

    override func didChangeText() {
        flush()
        super.didChangeText()
    }

    private func flush() {
        guard !pending.isEmpty || !crossed.isEmpty else { return }
        let ranges = pending
        pending = []
        let text = string as NSString
        let all = NSRange(location: 0, length: text.length)
        var whole = false
        var lines: [NSRange] = []
        for r in ranges {
            let clamped = NSIntersectionRange(r, all)
            let line = text.lineRange(for: NSRange(location: min(r.location, text.length), length: clamped.length))
            if text.substring(with: line).contains("```") { whole = true }
            lines.append(line)
        }
        if whole { restyle(all) } else { lines.forEach(restyle) }
        if !crossed.isEmpty {
            let gone = crossed
            crossed = []
            onResolve?(gone.map { h in
                var h = h
                let lo = min(h.range.location, all.length)
                h.range = NSRange(location: lo, length: min(NSMaxRange(h.range), all.length) - lo)
                return h
            }, .rewritten)
        }
        if review.hunks.contains(where: { $0.range.length == 0 }) || reviewed != review.hunks.count {
            reviewed = review.hunks.count
            setNeedsDisplay(visibleRect)
        }
        onReview?()
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
        let text = storage.string as NSString
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
                let marker = active ? m.markers.first.map { text.substring(with: $0) } ?? "" : ""
                storage.addAttributes([
                    .font: font,
                    .paragraphStyle: Theme.paragraph(lineHeight: ceil(font.pointSize * 1.3), before: level == 1 ? 0 : 10, after: 4,
                                                     hanging: Theme.width(marker, font)),
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
                let font = Theme.italic(Theme.body)
                let marker = active ? m.markers.first.map { text.substring(with: $0) } ?? "" : ""
                storage.addAttributes([
                    .font: font, .foregroundColor: Theme.soft, .quote: true,
                    .paragraphStyle: Theme.paragraph(lineHeight: 30, indent: 22, hanging: Theme.width(marker, font)),
                ], range: full)
            case .list:
                storage.addAttributes([.foregroundColor: Theme.accent], range: r)
                var end = NSMaxRange(r)
                while end < NSMaxRange(full), let c = Unicode.Scalar(text.character(at: end)), c == " " || c == "\t" { end += 1 }
                let leading = text.substring(with: NSRange(location: full.location, length: r.location - full.location))
                let prefix = text.substring(with: NSRange(location: full.location, length: end - full.location))
                let indent = Theme.width(leading, Theme.body)
                storage.addAttribute(.paragraphStyle, value: Theme.paragraph(lineHeight: 30, after: 2, indent: indent,
                                                                             hanging: Theme.width(prefix, Theme.body) - indent), range: full)
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
        for h in review.hunks where h.range.length > 0 {
            let overlap = NSIntersectionRange(h.range, full)
            guard overlap.length > 0 else { continue }
            let flagged = !h.flags.isEmpty
            storage.addAttributes([
                .backgroundColor: Theme.pending,
                .underlineStyle: (flagged ? NSUnderlineStyle([.single, .patternDot]) : .single).rawValue,
                .underlineColor: Theme.accent.withAlphaComponent(flagged ? 0.95 : 0.45),
            ], range: overlap)
        }
        for (r, attributes) in marks {
            let overlap = NSIntersectionRange(r, full)
            if overlap.length > 0 { storage.addAttributes(attributes, range: overlap) }
        }
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let tlm = textLayoutManager, let tcs = textContentStorage, let storage = textStorage else { return }
        let origin = textContainerOrigin
        let x = origin.x + Theme.hang + 2
        Theme.faint.setFill()
        let start = tlm.textLayoutFragment(for: CGPoint(x: 0, y: max(0, rect.minY - origin.y)))?.rangeInElement.location ?? tlm.documentRange.location
        tlm.enumerateTextLayoutFragments(from: start, options: [.ensuresLayout]) { fragment in
            let frame = fragment.layoutFragmentFrame.offsetBy(dx: origin.x, dy: origin.y)
            if frame.minY > rect.maxY { return false }
            guard frame.maxY >= rect.minY else { return true }
            let at = tcs.offset(from: tcs.documentRange.location, to: fragment.rangeInElement.location)
            if at < storage.length, storage.attribute(.quote, at: at, effectiveRange: nil) != nil {
                NSBezierPath(roundedRect: NSRect(x: x, y: frame.minY + 4, width: 2.5, height: frame.height - 8), xRadius: 1.25, yRadius: 1.25).fill()
            }
            return true
        }
        Theme.accent.setFill()
        for h in review.hunks where h.range.length == 0 {
            guard let seg = segments(NSRange(location: h.range.location, length: 0)).first, seg.intersects(rect.insetBy(dx: 0, dy: -40)) else { continue }
            NSBezierPath(roundedRect: NSRect(x: seg.minX - 1, y: seg.minY + 6, width: 2, height: max(seg.height - 12, 12)), xRadius: 1, yRadius: 1).fill()
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
        onCaret?()
    }
}

extension QuillTextView: NSTextStorageDelegate {
    nonisolated func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters) else { return }
        MainActor.assumeIsolated {
            pending.append(editedRange)
            guard !programmatic else { return }
            cross(NSRange(location: editedRange.location, length: editedRange.length - delta), length: editedRange.length)
        }
    }
}
