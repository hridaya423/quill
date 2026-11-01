import AppKit
import Testing
@testable import Quill

@MainActor
struct FormatTests {
    func view(_ text: String) -> QuillTextView {
        let (scroll, view) = QuillTextView.make()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = scroll
        scroll.frame = window.contentView!.bounds
        view.text = text
        return view
    }

    @Test func boldWrapsThenUnwraps() {
        let v = view("make this strong")
        v.setSelectedRange(NSRange(location: 10, length: 6))
        v.bold(nil)
        #expect(v.string == "make this **strong**")
        #expect(v.selectedRange() == NSRange(location: 12, length: 6))
        v.bold(nil)
        #expect(v.string == "make this strong")
        #expect(v.selectedRange() == NSRange(location: 10, length: 6))
    }

    @Test func boldUndoes() {
        let v = view("make this strong")
        v.setSelectedRange(NSRange(location: 10, length: 6))
        v.bold(nil)
        v.undoManager?.undo()
        #expect(v.string == "make this strong")
    }

    @Test func emptySelectionLeavesCaretBetweenMarkers() {
        let v = view("a ")
        v.setSelectedRange(NSRange(location: 2, length: 0))
        v.italic(nil)
        #expect(v.string == "a **")
        #expect(v.selectedRange() == NSRange(location: 3, length: 0))
    }

    @Test func headingSetsChangesAndClearsLevel() {
        let v = view("Title\nbody")
        v.setSelectedRange(NSRange(location: 2, length: 0))
        let item = NSMenuItem()
        item.tag = 2
        v.heading(item)
        #expect(v.string == "## Title\nbody")
        item.tag = 1
        v.heading(item)
        #expect(v.string == "# Title\nbody")
        v.heading(item)
        #expect(v.string == "Title\nbody")
    }

    @Test func untitledNoteTakesItsHeadingWhenLeft() throws {
        let vault = FileManager.default.temporaryDirectory.appending(path: "quill-title-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try "# Other\n".write(to: vault.appending(path: "Other.md"), atomically: true, encoding: .utf8)
        let ws = Workspace(vault: vault)
        let v = view("")
        ws.editor = v
        ws.refresh()
        ws.create()
        v.insertText("Spring launch plan", replacementRange: v.selectedRange())
        ws.edited()
        ws.open(vault.appending(path: "Other.md"))
        let names = try FileManager.default.contentsOfDirectory(atPath: vault.path).sorted()
        #expect(names == ["Other.md", "Spring launch plan.md"])
        #expect(try String(contentsOf: vault.appending(path: "Spring launch plan.md"), encoding: .utf8) == "# Spring launch plan\n")
    }
}
