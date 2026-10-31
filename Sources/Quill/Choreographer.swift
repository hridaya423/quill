import AppKit
import QuartzCore
import QuillCore

extension QuillTextView {
    @discardableResult
    func commit(_ changes: [Change]) -> [Change] {
        let text = string as NSString
        var inverse: [Change] = []
        var shift = 0
        let ordered = changes.sorted { $0.range.location < $1.range.location }
        let olds = ordered.map { text.substring(with: $0.range) }
        for (c, old) in zip(ordered, olds) {
            let r = NSRange(location: c.range.location + shift, length: c.range.length)
            replace(r, with: c.text)
            inverse.append(Change(range: NSRange(location: r.location, length: c.text.utf16.count), text: old))
            shift += c.text.utf16.count - c.range.length
        }
        return inverse
    }

    func registerUndo(_ inverse: [Change]) {
        guard let um = undoManager, !inverse.isEmpty else { return }
        breakUndoCoalescing()
        um.registerUndo(withTarget: self) { view in
            MainActor.assumeIsolated {
                view.registerUndo(view.commit(inverse))
            }
        }
        um.setActionName("Quill Edit")
    }
}

@MainActor private let easeOut = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
@MainActor private let easeInOut = CAMediaTimingFunction(controlPoints: 0.77, 0, 0.175, 1)
@MainActor private let drift = CAMediaTimingFunction(controlPoints: 0.45, 0, 0.85, 0.55)

@MainActor
final class Choreographer {
    private unowned let view: QuillTextView
    private var queue: [Change] = []
    private var current: Change?
    private var currentApplied = false
    private var inverse: [Change] = []
    private var task: Task<Void, Never>?
    private var caret: CALayer?
    var onFinish: ((Int) -> Void)?

    init(view: QuillTextView) {
        self.view = view
    }

    var isBusy: Bool { task != nil }

    func play(_ changes: [Change]) {
        guard !changes.isEmpty else { return }
        land()
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let inv = view.commit(changes)
            for c in inv { glow(c.range) }
            view.registerUndo(inv)
            onFinish?(changes.count)
            return
        }
        queue = shifted(changes)
        inverse = []
        let count = changes.count
        task = Task { [weak self] in
            guard let self else { return }
            while let next = self.queue.first, !Task.isCancelled {
                self.queue.removeFirst()
                self.current = next
                self.currentApplied = false
                await self.animate(next)
            }
            if !Task.isCancelled { self.finish(count) }
        }
    }

    func land() {
        guard let task else { return }
        task.cancel()
        self.task = nil
        if let c = current, !currentApplied {
            applyNow(c)
        }
        for c in queue { applyNow(c) }
        let count = inverse.count
        queue = []
        current = nil
        view.clearMarks(.foregroundColor)
        caret?.removeFromSuperlayer()
        caret = nil
        finish(count)
    }

    private func finish(_ count: Int) {
        task = nil
        current = nil
        view.registerUndo(inverse)
        inverse = []
        onFinish?(count)
    }

    private func applyNow(_ c: Change) {
        let old = (view.string as NSString).substring(with: c.range)
        view.replace(c.range, with: c.text)
        record(c, old: old)
        glow(NSRange(location: c.range.location, length: c.text.utf16.count))
    }

    private func record(_ c: Change, old: String) {
        inverse.append(Change(range: NSRange(location: c.range.location, length: c.text.utf16.count), text: old))
        currentApplied = true
    }

    private func pause(_ seconds: Double) async -> Bool {
        try? await Task.sleep(for: .seconds(seconds))
        return !Task.isCancelled
    }

    private func animate(_ c: Change) async {
        guard await reveal(c.range) else { return }
        let old = (view.string as NSString).substring(with: c.range)
        var dustImage: (CGImage, CGRect)?
        var strikes: [CALayer] = []

        if c.range.length > 0 {
            view.mark(c.range, [.foregroundColor: Theme.red])
            strikes = strike(view.segments(c.range))
            guard await pause(0.2) else { return }
            let rects = view.segments(c.range)
            if let bounds = rects.reduce(nil, { ($0 ?? $1).union($1) as CGRect? }) {
                let frame = bounds.insetBy(dx: -2, dy: -2).integral
                if let image = snapshot(frame) { dustImage = (image, frame) }
            }
        }

        if let (image, frame) = dustImage {
            view.mark(c.range, [.foregroundColor: NSColor.clear])
            dust(image, frame)
            for s in strikes { fadeAway(s, duration: 0.2) }
            guard await pause(0.3) else { return }
        }

        view.replace(c.range, with: c.text)
        record(c, old: old)
        let fresh = NSRange(location: c.range.location, length: c.text.utf16.count)
        if fresh.length > 0 {
            view.mark(fresh, [.foregroundColor: NSColor.clear])
            guard await type(fresh) else { return }
        } else {
            guard await pause(0.12) else { return }
        }
        glow(fresh)
        _ = await pause(0.14)
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

    private func snapshot(_ rect: CGRect) -> CGImage? {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: rect) else { return nil }
        let fx = view.fx.isHidden
        view.fx.isHidden = true
        view.drawsBackground = false
        view.cacheDisplay(in: rect, to: rep)
        view.drawsBackground = true
        view.fx.isHidden = fx
        return rep.cgImage
    }

    private func dust(_ image: CGImage, _ frame: CGRect) {
        let w = image.width, h = image.height
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return }

        let tile = max(2.0, (frame.width * frame.height / 1600).squareRoot())
        let cols = Int(ceil(frame.width / tile)), rows = Int(ceil(frame.height / tile))
        let sx = CGFloat(w) / frame.width, sy = CGFloat(h) / frame.height
        let container = CALayer()
        container.frame = frame
        view.fx.addSublayer(container)
        let scale = view.window?.backingScaleFactor ?? 2
        let now = CACurrentMediaTime()
        var longest = 0.0

        for row in 0..<rows {
            for col in 0..<cols {
                let px = Int((CGFloat(col) + 0.5) * tile * sx), py = Int((CGFloat(row) + 0.5) * tile * sy)
                var ink = false
                for dy in stride(from: -Int(tile * sy / 2), through: Int(tile * sy / 2), by: 1) {
                    for dx in stride(from: -Int(tile * sx / 2), through: Int(tile * sx / 2), by: 1) {
                        let x = min(w - 1, max(0, px + dx)), y = min(h - 1, max(0, py + dy))
                        if data[(y * w + x) * 4 + 3] > 24 { ink = true; break }
                    }
                    if ink { break }
                }
                guard ink else { continue }

                let piece = CALayer()
                piece.contents = image
                piece.contentsScale = scale
                let cell = CGRect(x: CGFloat(col) * tile, y: CGFloat(row) * tile, width: tile, height: tile)
                piece.frame = cell
                piece.contentsRect = CGRect(x: cell.minX / frame.width, y: cell.minY / frame.height,
                                            width: tile / frame.width, height: tile / frame.height)
                container.addSublayer(piece)

                let progress = Double(cell.midX / max(frame.width, 1))
                let delay = progress * 0.22 + Double.random(in: 0...0.06)
                let duration = Double.random(in: 0.5...0.85)
                longest = max(longest, delay + duration)

                let move = CABasicAnimation(keyPath: "position")
                move.fromValue = NSValue(point: CGPoint(x: cell.midX, y: cell.midY))
                move.toValue = NSValue(point: CGPoint(x: cell.midX + .random(in: 10...46), y: cell.midY - .random(in: 6...34)))
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = 1
                fade.toValue = 0
                let shrink = CABasicAnimation(keyPath: "transform.scale")
                shrink.fromValue = 1
                shrink.toValue = Double.random(in: 0.2...0.6)
                let group = CAAnimationGroup()
                group.animations = [move, fade, shrink]
                group.duration = duration
                group.beginTime = now + delay
                group.timingFunction = drift
                group.fillMode = .both
                group.isRemovedOnCompletion = false
                piece.add(group, forKey: "dust")
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + longest + 0.05) {
            container.removeFromSuperlayer()
        }
    }

    private func type(_ r: NSRange) async -> Bool {
        let text = view.string as NSString
        let total = min(0.75, max(0.14, Double(r.length) * 0.018))
        let start = CACurrentMediaTime()
        let caret = CALayer()
        caret.backgroundColor = Theme.accent.cgColor
        caret.cornerRadius = 1
        view.fx.addSublayer(caret)
        self.caret = caret
        var shown = 0
        while shown < r.length {
            guard await pause(1.0 / 120) else { return false }
            let t = min(1, (CACurrentMediaTime() - start) / total)
            var target = Int((Double(r.length) * t).rounded())
            if target > 0, target < r.length {
                let composed = text.rangeOfComposedCharacterSequence(at: r.location + target - 1)
                target = NSMaxRange(composed) - r.location
            }
            guard target > shown else { continue }
            shown = target
            view.clearMarks(.foregroundColor)
            if shown < r.length { view.mark(NSRange(location: r.location + shown, length: r.length - shown), [.foregroundColor: NSColor.clear]) }
            if let seg = view.segments(NSRange(location: r.location + shown, length: 0)).first {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                caret.frame = CGRect(x: seg.minX, y: seg.minY + 5, width: 2, height: max(seg.height - 10, 14))
                CATransaction.commit()
            }
        }
        fadeAway(caret, duration: 0.18)
        self.caret = nil
        return true
    }

    private func glow(_ r: NSRange) {
        guard r.length > 0 else { return }
        for rect in view.segments(r) {
            let line = CALayer()
            line.backgroundColor = Theme.green.withAlphaComponent(0.7).cgColor
            line.cornerRadius = 1
            line.frame = CGRect(x: rect.minX, y: rect.maxY - 6, width: rect.width, height: 2)
            line.opacity = 0
            view.fx.addSublayer(line)
            let pulse = CAKeyframeAnimation(keyPath: "opacity")
            pulse.values = [0, 1, 1, 0]
            pulse.keyTimes = [0, 0.06, 0.62, 1]
            pulse.duration = 2.6
            pulse.timingFunctions = [easeOut, easeOut, easeOut]
            line.add(pulse, forKey: "glow")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.65) { line.removeFromSuperlayer() }
        }
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
