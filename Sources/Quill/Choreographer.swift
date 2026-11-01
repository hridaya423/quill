import AppKit
import QuartzCore
import QuillCore

extension QuillTextView {
    @discardableResult
    func commit(_ changes: [Change], by source: EditSource) -> [Change] {
        let text = string as NSString
        var inverse: [Change] = []
        var shift = 0
        let ordered = changes.sorted { $0.range.location < $1.range.location }
        let olds = ordered.map { text.substring(with: $0.range) }
        for (c, old) in zip(ordered, olds) {
            let r = NSRange(location: c.range.location + shift, length: c.range.length)
            replace(r, with: c.text, by: source)
            inverse.append(Change(range: NSRange(location: r.location, length: c.text.utf16.count), text: old))
            shift += c.text.utf16.count - c.range.length
        }
        return inverse
    }

    @discardableResult
    func perform(_ changes: [Change], by source: EditSource, turn: Int) -> [Change] {
        let before = review
        let inverse = commit(changes, by: source)
        record(inverse, name: "Changes", turn: turn, before: before, after: review, back: true)
        return inverse
    }

    func record(_ inverse: [Change], name: String, turn: Int, before: Review, after: Review, back: Bool) {
        guard let um = undoManager else { return }
        breakUndoCoalescing()
        um.registerUndo(withTarget: self) { view in
            MainActor.assumeIsolated {
                if back, name == "Changes" {
                    let vanished = view.review.hunks.filter { h in !before.hunks.contains { $0.id == h.id } }
                    view.onResolve?(vanished, .undone)
                }
                let again = view.commit(inverse, by: .restore)
                view.setReview(before)
                view.record(again, name: name, turn: turn, before: after, after: before, back: !back)
                view.onUndo?(name, back)
            }
        }
        um.setActionName(name)
        um.setActionUserInfoValue(turn, forKey: .turn)
    }
}

@MainActor private let easeOut = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
@MainActor private let easeInOut = CAMediaTimingFunction(controlPoints: 0.77, 0, 0.175, 1)

@MainActor
final class Choreographer {
    private unowned let view: QuillTextView
    private var changes: [Change] = []
    private var source = EditSource.other
    private var turn = 0
    private var fresh: [NSRange]?
    private var layers: [CALayer] = []
    private var task: Task<Void, Never>?
    var onFinish: ((Int) -> Void)?

    init(view: QuillTextView) {
        self.view = view
    }

    var isBusy: Bool { task != nil }

    func play(_ changes: [Change], as source: EditSource, turn: Int) {
        guard !changes.isEmpty else { return }
        land()
        self.changes = changes.sorted { $0.range.location < $1.range.location }
        self.source = source
        self.turn = turn
        fresh = nil
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            settle()
            return
        }
        task = Task { [weak self] in
            guard let self else { return }
            await self.run()
            if !Task.isCancelled { self.finish() }
        }
    }

    func land() {
        guard task != nil else { return }
        settle()
    }

    private func settle() {
        task?.cancel()
        task = nil
        if fresh == nil { replaceAll() }
        view.clearMarks(.foregroundColor)
        for layer in layers { layer.removeFromSuperlayer() }
        finish()
    }

    private func finish() {
        task = nil
        layers = []
        let count = changes.count
        changes = []
        fresh = nil
        onFinish?(count)
    }

    private func replaceAll() {
        let inverse = view.perform(changes, by: source, turn: turn)
        fresh = inverse.map(\.range)
    }

    private func pause(_ seconds: Double) async -> Bool {
        try? await Task.sleep(for: .seconds(seconds))
        return !Task.isCancelled
    }

    private func run() async {
        guard let first = changes.first, await reveal(first.range) else { return }
        let cuts = changes.filter { $0.range.length > 0 }
        var hidden: [CALayer] = []
        if !cuts.isEmpty {
            let strikes = cuts.flatMap { strike(view.segments($0.range)) }
            layers += strikes
            guard await pause(0.24) else { return }
            var shots: [(CGImage, CGRect)] = []
            var struck: [CGRect] = []
            for c in cuts {
                let rects = view.segments(c.range)
                if let bounds = rects.reduce(nil, { ($0 ?? $1).union($1) as CGRect? }) {
                    let frame = bounds.insetBy(dx: -2, dy: -2).integral
                    if let image = snapshot(frame, clip: rects) { shots.append((image, frame)) }
                }
                struck += rects
            }
            cover(struck, &hidden)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for s in strikes { s.removeFromSuperlayer() }
            for shot in shots { lift(shot.0, shot.1) }
            CATransaction.commit()
            guard await pause(0.3) else { return }
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        replaceAll()
        for layer in hidden { layer.removeFromSuperlayer() }
        let typed = (fresh ?? []).filter { $0.length > 0 }
        var pools = typed.map { _ in [CALayer]() }
        for (i, r) in typed.enumerated() { cover(view.segments(r), &pools[i]) }
        CATransaction.commit()
        guard !typed.isEmpty else {
            _ = await pause(0.12)
            return
        }
        _ = await type(typed, &pools)
        for mask in pools.joined() { mask.removeFromSuperlayer() }
    }

    private var paper: CGColor {
        var color = Theme.paper.cgColor
        view.effectiveAppearance.performAsCurrentDrawingAppearance { color = Theme.paper.cgColor }
        return color
    }

    private func cover(_ rects: [CGRect], _ pool: inout [CALayer]) {
        let paper = paper
        while pool.count < rects.count {
            let mask = CALayer()
            mask.backgroundColor = paper
            view.fx.insertSublayer(mask, at: 0)
            pool.append(mask)
            layers.append(mask)
        }
        for (i, mask) in pool.enumerated() {
            mask.isHidden = i >= rects.count
            if i < rects.count {
                let r = rects[i]
                mask.frame = CGRect(x: r.minX, y: r.minY, width: r.width + 1, height: r.height)
            }
        }
    }

    private func reveal(_ r: NSRange) async -> Bool {
        guard let scroll = view.enclosingScrollView else { return true }
        let clip = scroll.contentView
        let target = view.segments(r).first ?? view.segments(NSRange(location: r.location, length: 0)).first
        guard let rect = target else { return true }
        let visible = clip.documentVisibleRect.insetBy(dx: 0, dy: 96)
        if visible.contains(CGPoint(x: visible.midX, y: rect.midY)) { return true }
        let maxY = max(0, view.frame.height - clip.bounds.height)
        let y = min(maxY, max(0, rect.midY - clip.bounds.height * 0.4))
        await NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.45
            ctx.timingFunction = easeInOut
            ctx.allowsImplicitAnimation = true
            clip.animator().setBoundsOrigin(NSPoint(x: clip.bounds.origin.x, y: y))
        }
        scroll.reflectScrolledClipView(clip)
        return !Task.isCancelled
    }

    private func strike(_ rects: [CGRect]) -> [CALayer] {
        rects.map { rect in
            let line = CAShapeLayer()
            let path = CGMutablePath()
            let y = rect.minY + rect.height * 0.56
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
            line.path = path
            line.strokeColor = Theme.red.cgColor
            line.lineWidth = 1.6
            line.lineCap = .round
            view.fx.addSublayer(line)
            let grow = CABasicAnimation(keyPath: "strokeEnd")
            grow.fromValue = 0
            grow.toValue = 1
            grow.duration = 0.16
            grow.timingFunction = easeOut
            line.add(grow, forKey: "grow")
            return line
        }
    }

    private func snapshot(_ rect: CGRect, clip: [CGRect]) -> CGImage? {
        guard let tlm = view.textLayoutManager else { return nil }
        let scale = view.window?.backingScaleFactor ?? 2
        let w = Int(rect.width * scale), h = Int(rect.height * scale)
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: scale, y: -scale)
        ctx.translateBy(x: -rect.minX, y: -rect.minY)
        ctx.clip(to: clip.map { $0.insetBy(dx: -1, dy: 0) })
        let origin = view.textContainerOrigin
        let start = tlm.textLayoutFragment(for: CGPoint(x: 0, y: max(0, rect.minY - origin.y)))?.rangeInElement.location ?? tlm.documentRange.location
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            tlm.enumerateTextLayoutFragments(from: start, options: [.ensuresLayout]) { fragment in
                let frame = fragment.layoutFragmentFrame.offsetBy(dx: origin.x, dy: origin.y)
                if frame.minY > rect.maxY { return false }
                fragment.draw(at: frame.origin, in: ctx)
                return true
            }
            ctx.setStrokeColor(Theme.red.cgColor)
            ctx.setLineWidth(1.6)
            ctx.setLineCap(.round)
            for r in clip {
                let y = r.minY + r.height * 0.56
                ctx.strokeLineSegments(between: [CGPoint(x: r.minX, y: y), CGPoint(x: r.maxX, y: y)])
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }

    private func lift(_ image: CGImage, _ frame: CGRect) {
        let layer = CALayer()
        layer.contents = image
        layer.contentsScale = view.window?.backingScaleFactor ?? 2
        layer.frame = frame
        view.fx.addSublayer(layer)
        layers.append(layer)
        CATransaction.begin()
        CATransaction.setCompletionBlock { layer.removeFromSuperlayer() }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        let rise = CABasicAnimation(keyPath: "position.y")
        rise.byValue = -6
        let group = CAAnimationGroup()
        group.animations = [fade, rise]
        group.duration = 0.32
        group.timingFunction = easeOut
        layer.opacity = 0
        layer.add(group, forKey: "lift")
        CATransaction.commit()
    }

    private func type(_ ranges: [NSRange], _ pools: inout [[CALayer]]) async -> Bool {
        let text = view.string as NSString
        let longest = ranges.map(\.length).max() ?? 0
        let total = min(0.8, max(0.16, Double(longest) * 0.016))
        let start = CACurrentMediaTime()
        let carets = ranges.prefix(8).map { _ in
            let caret = CALayer()
            caret.backgroundColor = Theme.accent.cgColor
            caret.cornerRadius = 1
            view.fx.addSublayer(caret)
            return caret
        }
        layers += carets
        var shown = Array(repeating: 0, count: ranges.count)
        while zip(shown, ranges).contains(where: { $0 < $1.length }) {
            guard await pause(1.0 / 120) else { return false }
            let t = min(1, (CACurrentMediaTime() - start) / total)
            var moved = false
            for (i, r) in ranges.enumerated() {
                var target = Int((Double(r.length) * t).rounded())
                if target > 0, target < r.length {
                    target = NSMaxRange(text.rangeOfComposedCharacterSequence(at: r.location + target - 1)) - r.location
                }
                if target > shown[i] { shown[i] = target; moved = true }
            }
            guard moved else { continue }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for (i, r) in ranges.enumerated() {
                let rest = NSRange(location: r.location + shown[i], length: r.length - shown[i])
                cover(rest.length > 0 ? view.segments(rest) : [], &pools[i])
                if i < carets.count, let seg = view.segments(NSRange(location: rest.location, length: 0)).first {
                    carets[i].frame = CGRect(x: seg.minX, y: seg.minY + 5, width: 2, height: max(seg.height - 10, 14))
                }
            }
            CATransaction.commit()
        }
        for caret in carets { fadeAway(caret, duration: 0.18) }
        return true
    }

    private func fadeAway(_ layer: CALayer, duration: Double) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(duration)
        CATransaction.setAnimationTimingFunction(easeOut)
        CATransaction.setCompletionBlock { layer.removeFromSuperlayer() }
        layer.opacity = 0
        CATransaction.commit()
    }
}
