import AppKit
import Testing
@testable import Quill

@MainActor
func openPage(_ text: String, dark: Bool = false, face: String = "sans") async throws -> (Page, NSWindow) {
    let page = Page()
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 1000), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    window.contentView = page
    NSApplication.shared.setActivationPolicy(.accessory)
    window.orderFront(nil)
    window.setFrameOrigin(NSPoint(x: -6000, y: 200))
    try await until { page.ready }
    page.face(face)
    page.load(text)
    try await Task.sleep(for: .milliseconds(200))
    return (page, window)
}

@MainActor
func until(_ timeout: Double = 4, _ done: () async -> Bool) async throws {
    let start = Date()
    while await !done() {
        guard Date().timeIntervalSince(start) < timeout else {
            Issue.record("timed out")
            return
        }
        try await Task.sleep(for: .milliseconds(20))
    }
}

@MainActor
func type(_ page: Page, _ text: String, at location: Int? = nil) async throws {
    let at = location ?? page.selectedRange().location
    let json = String(data: try JSONEncoder().encode(text), encoding: .utf8)!
    _ = try await page.evaluateJavaScript("quill.view.dispatch({changes: {from: \(at), insert: \(json)}, selection: {anchor: \(at) + \(json).length}, userEvent: 'input.type'})")
    try await until { page.version > 0 && page.text.contains(text) }
}

@MainActor
func still(_ page: Page) async throws {
    _ = try await page.evaluateJavaScript("if (!document.getElementById('settle')) { const s = document.createElement('style'); s.id = 'settle'; s.textContent = '*, *::before, *::after { transition: none !important; animation: none !important; }'; document.head.appendChild(s) } quill.view.measure()")
}
