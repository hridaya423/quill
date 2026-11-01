import AppKit
import Foundation
import Testing
@testable import Quill

@MainActor
@Test func keystrokesStayInsideAFrame() throws {
    let fixture = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appending(path: "../../scripts/fixtures/pitch.md"), encoding: .utf8)
    let doc = Array(repeating: fixture + "\n- a list item with **bold** and `code`\n\n> a quote line\n\n", count: 250).joined()
    let (scroll, view) = QuillTextView.make()
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 800), styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = scroll
    scroll.frame = window.contentView!.bounds
    view.text = doc
    let middle = (view.string as NSString).length / 2
    view.setSelectedRange(NSRange(location: middle, length: 0))
    view.scrollRangeToVisible(view.selectedRange())
    view.layoutSubtreeIfNeeded()

    var samples: [Double] = []
    for c in "The quick brown fox jumps over **the lazy** dog, then keeps typing for a while. " {
        let start = CFAbsoluteTimeGetCurrent()
        view.insertText(String(c), replacementRange: view.selectedRange())
        view.textLayoutManager?.textViewportLayoutController.layoutViewport()
        samples.append((CFAbsoluteTimeGetCurrent() - start) * 1000)
    }
    let cold = samples.removeFirst()
    samples.sort()
    let p50 = samples[samples.count / 2], worst = samples.last!
    print(String(format: "doc %d chars, cold keystroke %.2fms, warm p50 %.2fms max %.2fms", (doc as NSString).length, cold, p50, worst))
    #expect(worst < 8)
    #expect(cold < 16)
}
