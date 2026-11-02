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
    try await Task.sleep(for: .milliseconds(400))
    #expect(editor.chrome.headings.count == 30)
    let rail = try #require(editor.view.subviews.first { $0 is NSHostingView<Rail> })
    let margin = rail.convert(NSPoint(x: rail.bounds.width + 60, y: rail.bounds.midY), to: nil)
    #expect(window.contentView!.superview!.hitTest(margin) is QuillTextView)
    for _ in 0..<8 {
        withAnimation(.easeOut(duration: 0.16)) { editor.chrome.outlining.toggle() }
        for _ in 0..<12 {
            try await Task.sleep(for: .milliseconds(16))
            window.displayIfNeeded()
        }
    }
    editor.chrome.outlining = true
    for h in editor.chrome.headings.shuffled().prefix(6) {
        editor.jump(to: h)
        for _ in 0..<25 {
            try await Task.sleep(for: .milliseconds(16))
            window.displayIfNeeded()
        }
    }
    for y in stride(from: 0, through: 3000, by: 120) {
        editor.text.enclosingScrollView!.contentView.scroll(to: NSPoint(x: 0, y: y))
        try await Task.sleep(for: .milliseconds(16))
        window.displayIfNeeded()
    }
    editor.chrome.outlining = false
    for _ in 0..<12 {
        try await Task.sleep(for: .milliseconds(16))
        window.displayIfNeeded()
    }
    #expect(window.contentView!.superview!.hitTest(margin) is QuillTextView)
    window.close()
}
