import AppKit
import SwiftUI
import Testing
@testable import Quill

@MainActor
@Test(arguments: [420, 560, 820])
func openingTheOutlineKeepsTheWindowLayoutStable(height: Int) async throws {
    let vault = FileManager.default.temporaryDirectory.appending(path: "quill-rail-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
    let note = vault.appending(path: "Outline.md")
    try (1...30).map { "## Section \($0)\n\nA paragraph of text for section \($0).\n" }.joined(separator: "\n").write(to: note, atomically: true, encoding: .utf8)
    let ws = Workspace(vault: vault)
    let editor = EditorController(ws: ws)
    let split = NSSplitViewController()
    let side = NSSplitViewItem(sidebarWithViewController: NSHostingController(rootView: Sidebar(ws: ws, chrome: editor.chrome, settings: { _ in })))
    side.minimumThickness = 210
    split.addSplitViewItem(side)
    let main = NSSplitViewItem(viewController: editor)
    main.titlebarSeparatorStyle = .none
    split.addSplitViewItem(main)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1240, height: height),
                          styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.contentViewController = split
    window.setContentSize(NSSize(width: 1240, height: height))
    let accessory = NSTitlebarAccessoryViewController()
    accessory.view = NSView(frame: NSRect(x: 0, y: 0, width: 38, height: 28))
    accessory.layoutAttribute = .left
    window.addTitlebarAccessoryViewController(accessory)
    NSApplication.shared.setActivationPolicy(.accessory)
    window.orderFront(nil)
    window.setFrameOrigin(NSPoint(x: -6000, y: 200))
    ws.refresh()
    ws.open(note)
    let page = editor.text!
    func js(_ script: String) async throws -> Any? { try await page.evaluateJavaScript(script) }
    try await until(8) {
        guard page.ready else { return false }
        return (try? await js("document.querySelectorAll('.cm-rail-tick').length")) as? Int == 30
    }
    func on() async throws -> Int { try await js("[...document.querySelectorAll('.cm-rail-tick')].findIndex(t => t.classList.contains('cm-rail-on'))") as? Int ?? -2 }
    func offset(_ n: Int) async throws -> Double {
        try await js("(() => { const v = quill.view; const at = v.state.doc.toString().indexOf('## Section \(n)\\n'); const c = v.coordsAtPos(at); return c ? c.top - v.scrollDOM.getBoundingClientRect().top : null })()") as? Double ?? .nan
    }
    #expect(try await js("quill.view.scrollDOM.scrollHeight > quill.view.scrollDOM.clientHeight * 2 && document.scrollingElement.scrollHeight <= innerHeight") as? Bool == true)
    #expect(try await js("document.querySelectorAll('.cm-rail-tick').length") as? Int == 30)
    try await still(page)
    try await until { (try? await on()) == 0 }
    for n in [25, 3, 17] {
        _ = try await js("document.querySelectorAll('.cm-rail-row')[\(n - 1)].click()")
        try await still(page)
        try await until { (try? await offset(n)).map { abs($0 - 64) < 3 } ?? false }
        #expect(abs(try await offset(n) - 64) < 3)
        try await until { (try? await on()) == n - 1 }
        let line = page.buffer.range(of: "## Section \(n)\n")
        #expect(page.selectedRange() == NSRange(location: NSMaxRange(line) - 1, length: 0))
    }
    _ = try await js("document.querySelectorAll('.cm-rail-row')[29].click()")
    try await still(page)
    try await until { await (try? js("quill.view.scrollDOM.scrollTop + quill.view.scrollDOM.clientHeight >= quill.view.scrollDOM.scrollHeight - 2")) as? Bool == true }
    try await until { (try? await on()) == 29 }
    for n in [8, 22] {
        _ = try await js("(() => { const v = quill.view; const at = v.state.doc.toString().indexOf('## Section \(n)\\n'); v.scrollDOM.scrollTop += v.lineBlockAt(at).top + v.documentTop - v.scrollDOM.getBoundingClientRect().top - 40 })()")
        try await until { (try? await on()) == n - 1 }
    }
    _ = try await js("quill.view.scrollDOM.scrollTop = 0")
    try await until { (try? await on()) == 0 }
    let margin = page.convert(NSPoint(x: 70, y: page.bounds.midY), to: nil)
    #expect(window.contentView!.superview!.hitTest(margin).map { $0.isDescendant(of: page) } == true)
    window.close()
}
