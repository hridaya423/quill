import AppKit
import QuillCore

extension NSAttributedString.Key {
    static let quote = NSAttributedString.Key("QuillQuote")
    static let fence = NSAttributedString.Key("QuillFence")
    static let ornament = NSAttributedString.Key("QuillOrnament")
    static let target = NSAttributedString.Key("QuillTarget")
    static let chip = NSAttributedString.Key("QuillChip")
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
    var focused: Int? {
        didSet {
            guard focused != oldValue else { return }
            for id in [focused, oldValue].compactMap({ $0 }) {
                if let h = review.hunk(id) { restyle(h.range) }
            }
            needsDisplay = true
        }
    }
    private var presence: CALayer?
    private var growing: Set<Int> = []
    private var warming = false
    private var sweeper: Timer?
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
        selectedTextAttributes = [.backgroundColor: Theme.selection]
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
        let link = hit(point) != nil
        if link != pointing {
            pointing = link
            (link ? NSCursor.pointingHand : NSCursor.iBeam).set()
        }
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
        let typed = (string as? String) ?? (string as? NSAttributedString)?.string ?? ""
        if typed == "[", let partial = wikiPartial(), partial.length == 0 {
            DispatchQueue.main.async { [weak self] in self?.complete(nil) }
        }
    }

    var noteTitles: () -> [String] = { [] }

    func wikiPartial() -> NSRange? {
        let text = string as NSString
        let caret = selectedRange()
        guard caret.length == 0, caret.location >= 2 else { return nil }
        let line = text.lineRange(for: NSRange(location: caret.location, length: 0))
        let before = text.substring(with: NSRange(location: line.location, length: caret.location - line.location))
        guard let open = before.range(of: "[[", options: .backwards), !before[open.upperBound...].contains("]") else { return nil }
        let start = line.location + (before[..<open.upperBound] as Substring).utf16.count
        return NSRange(location: start, length: caret.location - start)
    }

    override var rangeForUserCompletion: NSRange {
        wikiPartial() ?? super.rangeForUserCompletion
    }

    override func completions(forPartialWordRange charRange: NSRange, indexOfSelectedItem index: UnsafeMutablePointer<Int>) -> [String]? {
        guard charRange == wikiPartial() else { return super.completions(forPartialWordRange: charRange, indexOfSelectedItem: index) }
        let typed = (string as NSString).substring(with: charRange).lowercased()
        let titles = noteTitles().filter { typed.isEmpty || $0.lowercased().contains(typed) }
        index.pointee = titles.isEmpty ? -1 : 0
        return titles.sorted { a, b in
            let pa = a.lowercased().hasPrefix(typed), pb = b.lowercased().hasPrefix(typed)
            return pa != pb ? pa : false
        }
    }

    override func insertCompletion(_ word: String, forPartialWordRange charRange: NSRange, movement: Int, isFinal flag: Bool) {
        let wiki = charRange == wikiPartial() || (string as NSString).substring(to: charRange.location).hasSuffix("[[")
        guard wiki, flag, movement != NSTextMovement.cancel.rawValue else {
            return super.insertCompletion(word, forPartialWordRange: charRange, movement: movement, isFinal: flag)
        }
        let rest = string as NSString
        let closed = NSMaxRange(charRange) + 2 <= rest.length && rest.substring(with: NSRange(location: NSMaxRange(charRange), length: 2)) == "]]"
        super.insertCompletion(closed ? word : word + "]]", forPartialWordRange: charRange, movement: movement, isFinal: flag)
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.warm() }
        }
    }

    private func warm() {
        guard window != nil, review.isEmpty, let tlm = textLayoutManager, let tcs = textContentStorage,
              let fragment = tlm.textLayoutFragment(for: CGPoint(x: 0, y: max(0, visibleRect.minY - textContainerOrigin.y)))
        else { return }
        let text = string as NSString
        let p = paragraph(at: tcs.offset(from: tcs.documentRange.location, to: fragment.rangeInElement.location))
        guard p.length > 1 else { return }
        let at = NSMaxRange(p) - (text.character(at: NSMaxRange(p) - 1) == 10 ? 1 : 0)
        let callbacks = (onReview, onEdit, onResolve)
        let selection = selectedRanges
        (onReview, onEdit, onResolve) = (nil, nil, nil)
        warming = true
        undoManager?.disableUndoRegistration()
        replace(NSRange(location: at, length: 0), with: "\u{200B}", by: .agent(turn: 0, flags: []))
        CATransaction.flush()
        replace(NSRange(location: at, length: 1), with: "", by: .restore)
        setReview(Review())
        undoManager?.enableUndoRegistration()
        warming = false
        selectedRanges = selection
        (onReview, onEdit, onResolve) = callbacks
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
        let arrived = next.hunks.filter { h in review.hunk(h.id) == nil }
        review = next
        flush()
        grow(arrived)
    }

    private var still: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    private func grow(_ hunks: [Hunk]) {
        guard !still, !warming, window != nil else { return }
        for h in hunks {
            guard let bar = bar(h), bar.intersects(visibleRect) else { continue }
            growing.insert(h.id)
            let l = CALayer()
            l.backgroundColor = Theme.accent.withAlphaComponent(0.55).cgColor
            l.cornerRadius = 1
            l.anchorPoint = CGPoint(x: 0.5, y: 0)
            l.frame = bar
            fx.addSublayer(l)
            CATransaction.begin()
            CATransaction.setCompletionBlock { [weak self] in
                MainActor.assumeIsolated {
                    self?.growing.remove(h.id)
                    self?.setNeedsDisplay(bar.insetBy(dx: -2, dy: -2))
                    l.removeFromSuperlayer()
                }
            }
            let a = CABasicAnimation(keyPath: "transform.scale.y")
            a.fromValue = 0
            a.toValue = 1
            a.duration = 0.32
            a.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
            l.add(a, forKey: "grow")
            CATransaction.commit()
        }
        setNeedsDisplay(visibleRect)
    }

    private func crossfade(_ hunks: [Hunk], _ change: () -> Void) {
        let area = hunks.reduce(CGRect.null) { area, h in
            let p = paragraph(at: h.range.location)
            return segments(p).reduce(area) { $0.union($1) }.union(bar(h) ?? .null)
        }
        let shown = CGRect(x: textContainerOrigin.x, y: area.minY - 4, width: bounds.width - textContainerOrigin.x, height: area.height + 8).intersection(visibleRect)
        guard !still, !area.isNull, !shown.isEmpty, let rep = bitmapImageRepForCachingDisplay(in: shown) else { return change() }
        cacheDisplay(in: shown, to: rep)
        change()
        let l = CALayer()
        l.contents = rep.cgImage
        l.contentsScale = window?.backingScaleFactor ?? 2
        l.frame = shown
        fx.addSublayer(l)
        CATransaction.begin()
        CATransaction.setCompletionBlock { l.removeFromSuperlayer() }
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = 1
        a.toValue = 0
        a.duration = 0.2
        a.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
        l.opacity = 0
        l.add(a, forKey: "fade")
        CATransaction.commit()
    }

    func keep(_ hunks: [Hunk]) {
        let before = review
        var next = review
        let gone = hunks.compactMap { next.remove($0.id) }
        guard !gone.isEmpty else { return }
        crossfade(gone) { setReview(next) }
        onResolve?(gone.filter { !$0.touched }, .kept)
        onResolve?(gone.filter(\.touched), .rewritten)
        record([], name: gone.count == 1 ? "Keep Change" : "Keep Changes", turn: 0, before: before, after: review, back: true)
    }

    func revert(_ hunks: [Hunk]) {
        let before = review
        var next = review
        let gone = hunks.compactMap { next.remove($0.id) }
        guard !gone.isEmpty else { return }
        var inverse: [Change] = []
        crossfade(gone) {
            setReview(next)
            onResolve?(gone, .reverted)
            inverse = commit(gone.map { Change(range: $0.range, text: $0.old) }, by: .other)
        }
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
                storage.addAttributes([.font: Theme.mono, .chip: Theme.sheet], range: r)
            case .codeBlock:
                storage.addAttributes([.font: Theme.mono, .foregroundColor: Theme.soft, .fence: true, .paragraphStyle: Theme.paragraph(lineHeight: 24, indent: 18)], range: full)
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
                storage.addAttributes([.foregroundColor: Theme.soft], range: r)
                func skip(_ from: Int) -> Int {
                    var end = from
                    while end < NSMaxRange(full), let c = Unicode.Scalar(text.character(at: end)), c == " " || c == "\t" { end += 1 }
                    return end
                }
                let bullet = skip(NSMaxRange(r))
                let box = m.ornaments.first { if case .box = $0.kind { true } else { false } }.map { skip(NSMaxRange($0.range)) }
                let leading = Theme.width(text.substring(with: NSRange(location: full.location, length: r.location - full.location)), Theme.body)
                let marker = Theme.width(text.substring(with: NSRange(location: r.location, length: bullet - r.location)), Theme.body)
                let checkbox = box.map { Theme.width("[ ]", Theme.mono) + Theme.width(text.substring(with: NSRange(location: bullet + 3, length: $0 - bullet - 3)), Theme.body) } ?? 0
                storage.addAttribute(.paragraphStyle, value: Theme.paragraph(lineHeight: 30, after: 2, indent: leading + checkbox,
                                                                             hanging: marker + checkbox), range: full)
            case .strike:
                storage.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: Theme.soft], range: r)
            case .rule:
                storage.addAttribute(.foregroundColor, value: Theme.faint, range: full)
            case .highlight:
                storage.addAttribute(.chip, value: Theme.mark, range: r)
            case .done:
                storage.addAttribute(.foregroundColor, value: Theme.soft, range: r)
            }
        }
        for target in m.targets {
            storage.addAttribute(.target, value: (target.note ? "note:" : "url:") + target.to, range: target.range)
        }
        for o in m.ornaments where o.range.length > 0 {
            if case .box = o.kind { storage.addAttribute(.font, value: Theme.mono, range: o.range) }
            if active {
                storage.addAttribute(.foregroundColor, value: Theme.faint, range: o.range)
                continue
            }
            let kind: String = switch o.kind {
            case .bullet: "bullet"
            case .box(let checked): checked ? "checked" : "box"
            case .blank: "blank"
            case .rule: "rule"
            }
            storage.addAttributes([.foregroundColor: NSColor.clear, .ornament: kind], range: o.range)
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
            let on = h.id == focused
            var look: [NSAttributedString.Key: Any] = [
                .underlineStyle: (h.flags.isEmpty ? NSUnderlineStyle.single : [.single, .patternDot]).rawValue,
                .underlineColor: Theme.accent.withAlphaComponent(on || !h.flags.isEmpty ? 1 : 0.45),
            ]
            if on { look[.backgroundColor] = Theme.mark }
            storage.addAttributes(look, range: overlap)
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
        let column = (textContainer?.size.width ?? Theme.column) - Theme.hang
        let start = tlm.textLayoutFragment(for: CGPoint(x: 0, y: max(0, rect.minY - origin.y)))?.rangeInElement.location ?? tlm.documentRange.location
        var lo = Int.max, hi = 0
        var block: CGRect?
        func panel(_ r: CGRect) {
            Theme.sheet.setFill()
            NSBezierPath(roundedRect: CGRect(x: x - 2, y: r.minY - 2, width: column, height: r.height + 4), xRadius: 8, yRadius: 8).fill()
        }
        tlm.enumerateTextLayoutFragments(from: start, options: [.ensuresLayout]) { fragment in
            let frame = fragment.layoutFragmentFrame.offsetBy(dx: origin.x, dy: origin.y)
            if frame.minY > rect.maxY { return false }
            let at = tcs.offset(from: tcs.documentRange.location, to: fragment.rangeInElement.location)
            let end = tcs.offset(from: tcs.documentRange.location, to: fragment.rangeInElement.endLocation)
            let fenced = at < storage.length && storage.attribute(.fence, at: at, effectiveRange: nil) != nil
            if fenced {
                block = block.map { $0.union(frame) } ?? frame
            } else if let b = block {
                panel(b)
                block = nil
            }
            guard frame.maxY >= rect.minY else { return true }
            lo = min(lo, at)
            hi = max(hi, end)
            if at < storage.length, storage.attribute(.quote, at: at, effectiveRange: nil) != nil {
                Theme.faint.setFill()
                NSBezierPath(roundedRect: NSRect(x: x, y: frame.minY + 4, width: 2.5, height: frame.height - 8), xRadius: 1.25, yRadius: 1.25).fill()
            }
            return true
        }
        if let b = block { panel(b) }
        if lo < hi {
            storage.enumerateAttribute(.chip, in: NSRange(location: lo, length: min(hi, storage.length) - lo)) { value, r, _ in
                guard let color = value as? NSColor else { return }
                color.setFill()
                for seg in segments(r) {
                    NSBezierPath(roundedRect: seg.insetBy(dx: -3, dy: 0).insetBy(dx: 0, dy: max(0, (seg.height - 25) / 2)).offsetBy(dx: 0, dy: 1), xRadius: 4, yRadius: 4).fill()
                }
            }
            storage.enumerateAttribute(.ornament, in: NSRange(location: lo, length: min(hi, storage.length) - lo)) { value, r, _ in
                guard let kind = value as? String, let seg = segments(r).first else { return }
                ornament(kind, in: seg, column: CGRect(x: x, y: seg.minY, width: column, height: seg.height))
            }
        }
        for h in review.hunks where !growing.contains(h.id) && !warming {
            guard let bar = bar(h), bar.intersects(rect) else { continue }
            Theme.accent.withAlphaComponent(h.id == focused ? 1 : 0.55).setFill()
            NSBezierPath(roundedRect: bar, xRadius: 1, yRadius: 1).fill()
        }
    }

    private func ornament(_ kind: String, in seg: CGRect, column: CGRect) {
        let mid = seg.midY + 1.5
        switch kind {
        case "bullet":
            Theme.soft.setFill()
            NSBezierPath(ovalIn: CGRect(x: seg.midX - 5.75, y: mid - 2.75, width: 5.5, height: 5.5)).fill()
        case "box", "checked":
            let side: CGFloat = 15
            let box = CGRect(x: seg.minX + (seg.width - side) / 2, y: mid - side / 2, width: side, height: side)
            let shape = NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4)
            if kind == "box" {
                Theme.soft.withAlphaComponent(0.7).setStroke()
                shape.lineWidth = 1.3
                shape.stroke()
                return
            }
            Theme.accent.setFill()
            shape.fill()
            let tick = NSBezierPath()
            tick.move(to: CGPoint(x: box.minX + 3.8, y: box.midY + 0.2))
            tick.line(to: CGPoint(x: box.minX + 6.4, y: box.maxY - 4))
            tick.line(to: CGPoint(x: box.maxX - 3.6, y: box.minY + 4.2))
            tick.lineWidth = 1.9
            tick.lineCapStyle = .round
            tick.lineJoinStyle = .round
            Theme.paper.setStroke()
            tick.stroke()
        case "rule":
            Theme.rule.setFill()
            CGRect(x: column.minX, y: seg.midY.rounded(), width: column.width, height: 1).fill()
        default:
            break
        }
    }

    private func hit(_ point: NSPoint) -> (range: NSRange, value: String, box: Bool)? {
        guard let storage = textStorage, storage.length > 0 else { return nil }
        let index = characterIndexForInsertion(at: point)
        for at in [index, index - 1] where at >= 0 && at < storage.length {
            var r = NSRange()
            if let kind = storage.attribute(.ornament, at: at, effectiveRange: &r) as? String, kind == "box" || kind == "checked" {
                if segments(r).contains(where: { $0.insetBy(dx: -6, dy: -2).contains(point) }) { return (r, kind, true) }
            }
            if let raw = storage.attribute(.target, at: at, longestEffectiveRange: &r, in: NSRange(location: 0, length: storage.length)) as? String,
               NSIntersectionRange(text(lineAt: at), activeLines).length == 0,
               segments(r).contains(where: { $0.insetBy(dx: -1, dy: -1).contains(point) }) {
                return (r, raw, false)
            }
        }
        return nil
    }

    private func text(lineAt at: Int) -> NSRange {
        (string as NSString).lineRange(for: NSRange(location: at, length: 0))
    }

    var onOpenNote: ((String) -> Void)?
    private var pointing = false

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard event.clickCount == 1, !event.modifierFlags.contains(.shift), let found = hit(point) else {
            return super.mouseDown(with: event)
        }
        if found.box {
            let next = found.value == "checked" ? "[ ]" : "[x]"
            if shouldChangeText(in: found.range, replacementString: next) {
                textStorage?.replaceCharacters(in: found.range, with: next)
                didChangeText()
                undoManager?.setActionName(next == "[x]" ? "Check" : "Uncheck")
            }
        } else if found.value.hasPrefix("note:") {
            onOpenNote?(String(found.value.dropFirst(5)))
        } else if let url = URL(string: String(found.value.dropFirst(4))), url.scheme != nil {
            NSWorkspace.shared.open(url)
        }
    }

    override func cursorUpdate(with event: NSEvent) {
        if pointing { NSCursor.pointingHand.set() } else { super.cursorUpdate(with: event) }
    }

    func bar(_ h: Hunk) -> CGRect? {
        let rects = segments(h.range.length > 0 ? h.range : NSRange(location: h.range.location, length: 0))
        guard let first = rects.first, let last = rects.last else { return nil }
        return CGRect(x: textContainerOrigin.x + 14, y: first.minY + 5, width: 2, height: max(last.maxY - first.minY - 10, 14))
    }

    func paragraph(at location: Int) -> NSRange {
        let text = string as NSString
        return text.paragraphRange(for: NSRange(location: min(location, text.length), length: 0))
    }

    func present(_ r: NSRange?) {
        sweeper?.invalidate()
        sweeper = nil
        guard let r, let first = segments(NSRange(location: r.location, length: 0)).first else {
            guard let presence else { return }
            self.presence = nil
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.25)
            CATransaction.setCompletionBlock { presence.removeFromSuperlayer() }
            presence.opacity = 0
            CATransaction.commit()
            return
        }
        let end = segments(NSRange(location: max(r.location, NSMaxRange(r) - 1), length: 0)).first ?? first
        let frame = CGRect(x: textContainerOrigin.x + 13, y: first.minY + 4, width: 4, height: max(end.maxY - first.minY - 8, 16))
        let layer = presence ?? {
            let l = CALayer()
            l.backgroundColor = Theme.accent.withAlphaComponent(0.85).cgColor
            l.cornerRadius = 2
            l.frame = frame
            l.opacity = 0
            fx.addSublayer(l)
            presence = l
            if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                let breathe = CABasicAnimation(keyPath: "opacity")
                breathe.fromValue = 0.4
                breathe.toValue = 1
                breathe.duration = 0.8
                breathe.autoreverses = true
                breathe.repeatCount = .infinity
                breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                l.add(breathe, forKey: "breathe")
            }
            return l
        }()
        layer.opacity = 0.8
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if !reduce, layer.frame != frame {
            for key in ["position", "bounds.size"] {
                let spring = CASpringAnimation(perceptualDuration: 0.45, bounce: 0)
                spring.keyPath = key
                spring.fromValue = key == "position" ? NSValue(point: layer.presentation()?.position ?? layer.position)
                    : NSValue(size: layer.presentation()?.bounds.size ?? layer.bounds.size)
                layer.add(spring, forKey: key)
            }
        }
        layer.frame = frame
        CATransaction.commit()
    }

    func sweep() {
        guard sweeper == nil else { return }
        let text = string as NSString
        guard text.length > 0, let tlm = textLayoutManager, let tcs = textContentStorage else { return }
        let visible = visibleRect
        var paragraphs: [NSRange] = []
        tlm.enumerateTextLayoutFragments(from: tlm.textLayoutFragment(for: CGPoint(x: 0, y: max(0, visible.minY - textContainerOrigin.y)))?.rangeInElement.location ?? tlm.documentRange.location,
                                         options: [.ensuresLayout]) { fragment in
            let frame = fragment.layoutFragmentFrame.offsetBy(dx: 0, dy: textContainerOrigin.y)
            if frame.minY > visible.maxY { return false }
            let at = tcs.offset(from: tcs.documentRange.location, to: fragment.rangeInElement.location)
            let p = paragraph(at: at)
            if !text.substring(with: p).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, paragraphs.last != p { paragraphs.append(p) }
            return true
        }
        guard !paragraphs.isEmpty else { return }
        var i = 0
        present(paragraphs[0])
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        sweeper = Timer.scheduledTimer(withTimeInterval: 0.9, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                i = (i + 1) % paragraphs.count
                let timer = self.sweeper
                self.present(paragraphs[i])
                self.sweeper = timer
            }
        }
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        let text = string as NSString
        let sel = selectedRange()
        guard NSMaxRange(sel) <= text.length else { return }
        let lines = text.lineRange(for: NSRange(location: sel.location, length: 0))
        if sel.length == 0, !stillSelecting, lines != activeLines {
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
