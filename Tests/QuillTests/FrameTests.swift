import AppKit
import Foundation
import Testing
import QuillCore
@testable import Quill

@MainActor
final class FrameProbe: NSObject {
    private var link: CADisplayLink?
    private var stamps: [CFTimeInterval] = []
    private(set) var phases: [(String, Int)] = []

    init(_ view: NSView) {
        super.init()
        link = view.displayLink(target: self, selector: #selector(tick))
        link?.add(to: .main, forMode: .common)
    }

    @objc private func tick(_ link: CADisplayLink) { stamps.append(link.timestamp) }

    func phase(_ name: String) { phases.append((name, stamps.count)) }

    func stop() { link?.invalidate() }

    func report() -> [(String, Int, Double)] {
        let bounds = phases.map(\.1) + [stamps.count]
        return phases.enumerated().map { i, p in
            let slice = Array(stamps[max(0, p.1 - 1)..<bounds[i + 1]])
            let gaps = zip(slice.dropFirst(), slice).map { ($0 - $1) * 1000 }
            return (p.0, gaps.count, gaps.max() ?? 0)
        }
    }
}

@MainActor
@Suite(.serialized)
struct FrameTests {
    nonisolated static let enabled = ProcessInfo.processInfo.environment["QUILL_FRAMES"] != nil
    nonisolated static let strip = ProcessInfo.processInfo.environment["QUILL_STRIP"]

    static func film(_ window: NSWindow, _ name: String, count: Int) {
        guard let strip else { return }
        let id = window.windowNumber
        Task.detached {
            for i in 0..<count {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                p.arguments = ["-x", "-o", "-l", "\(id)", "\(strip)/\(name)-\(String(format: "%02d", i)).png"]
                try? p.run()
                p.waitUntilExit()
            }
        }
    }

    @Test(.enabled(if: enabled)) func changeAndPresenceAnimationsHoldTheFrame() async throws {
        Brand.register()
        let fixture = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appending(path: "../../scripts/fixtures/pitch.md"), encoding: .utf8)
        let (scroll, text) = QuillTextView.make()
        let window = NSWindow(contentRect: NSRect(x: 40, y: 40, width: 1100, height: 760), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = scroll
        scroll.frame = window.contentView!.bounds
        if let look = ProcessInfo.processInfo.environment["QUILL_LOOK"] { window.appearance = NSAppearance(named: look == "dark" ? .darkAqua : .aqua) }
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        text.text = fixture
        text.layoutSubtreeIfNeeded()
        let choreographer = Choreographer(view: text)
        var finished = false
        choreographer.onFinish = { _ in finished = true }
        try await Task.sleep(for: .milliseconds(600))

        let probe = FrameProbe(text)
        defer { probe.stop() }
        try await Task.sleep(for: .milliseconds(300))

        probe.phase("idle")
        try await Task.sleep(for: .milliseconds(500))

        probe.phase("presence sweep")
        Self.film(window, "1-sweep", count: 6)
        text.sweep()
        try await Task.sleep(for: .seconds(2.2))

        probe.phase("presence move")
        let s = text.string as NSString
        text.present(text.paragraph(at: s.range(of: "Writers lose hours").location))
        try await Task.sleep(for: .milliseconds(700))
        text.present(nil)

        probe.phase("arrival")
        Self.film(window, "2-arrival", count: 14)
        let changes = [
            Change(range: s.range(of: "We are basically trying to kind of build a tool that maybe helps people write better, in a way."), text: "We build a tool that helps people write better."),
            Change(range: s.range(of: "lose hours"), text: "lose days"),
        ]
        choreographer.play(changes, as: .agent(turn: 1, flags: []), turn: 1)
        for _ in 0..<80 where !finished { try await Task.sleep(for: .milliseconds(50)) }
        try await Task.sleep(for: .milliseconds(400))

        probe.phase("keep")
        Self.film(window, "3-pending", count: 1)
        try await Task.sleep(for: .milliseconds(150))
        text.focused = text.review.hunks[0].id
        Self.film(window, "4-focused", count: 1)
        try await Task.sleep(for: .milliseconds(250))
        text.focused = nil
        Self.film(window, "5-keep", count: 4)
        text.keep([text.review.hunks[0]])
        try await Task.sleep(for: .milliseconds(400))

        probe.phase("revert")
        Self.film(window, "6-revert", count: 4)
        text.revert([text.review.hunks[0]])
        try await Task.sleep(for: .milliseconds(400))

        let rows = probe.report()
        var table = "| phase | frames | worst frame (ms) |\n|---|---|---|\n"
        for (name, n, worst) in rows { table += String(format: "| %@ | %d | %.1f |\n", name, n, worst) }
        print(table)
        if let out = ProcessInfo.processInfo.environment["QUILL_FRAMES"], !out.isEmpty {
            try table.write(toFile: out, atomically: true, encoding: .utf8)
        }
        #expect(finished)
        for (name, n, worst) in rows {
            #expect(n > 10, "\(name) recorded too few frames")
            #expect(worst <= 16.7, "\(name) dropped a frame: \(worst) ms")
        }
    }
}
