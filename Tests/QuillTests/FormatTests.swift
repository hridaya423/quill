import AppKit
import Testing
@testable import Quill

@MainActor
struct FormatTests {
    @Test func boldWrapsThenUnwraps() async throws {
        let (v, window) = try await openPage("make this strong")
        defer { window.close() }
        v.setSelectedRange(NSRange(location: 10, length: 6))
        v.bold(nil)
        try await until { v.text == "make this **strong**" }
        #expect(v.selectedRange() == NSRange(location: 12, length: 6))
        v.bold(nil)
        try await until { v.text == "make this strong" }
        #expect(v.selectedRange() == NSRange(location: 10, length: 6))
    }

    @Test func boldUndoes() async throws {
        let (v, window) = try await openPage("make this strong")
        defer { window.close() }
        v.setSelectedRange(NSRange(location: 10, length: 6))
        v.bold(nil)
        try await until { v.text == "make this **strong**" }
        v.undo(nil)
        try await until { v.text == "make this strong" }
    }

    @Test func emptySelectionLeavesCaretBetweenMarkers() async throws {
        let (v, window) = try await openPage("a ")
        defer { window.close() }
        v.setSelectedRange(NSRange(location: 2, length: 0))
        v.italic(nil)
        try await until { v.text == "a **" }
        #expect(v.selectedRange() == NSRange(location: 3, length: 0))
    }

    @Test func headingSetsChangesAndClearsLevel() async throws {
        let (v, window) = try await openPage("Title\nbody")
        defer { window.close() }
        v.setSelectedRange(NSRange(location: 2, length: 0))
        let item = NSMenuItem()
        item.tag = 2
        v.heading(item)
        try await until { v.text == "## Title\nbody" }
        item.tag = 1
        v.heading(item)
        try await until { v.text == "# Title\nbody" }
        v.heading(item)
        try await until { v.text == "Title\nbody" }
    }

    @Test func italicInsideBoldAddsEmphasisInsteadOfStrippingBold() async throws {
        let (v, window) = try await openPage("a **bold** b")
        defer { window.close() }
        v.setSelectedRange(NSRange(location: 4, length: 4))
        v.italic(nil)
        try await until { v.text == "a ***bold*** b" }
    }

    @Test func bodyTextKeepsHashtags() async throws {
        let (v, window) = try await openPage("#tag line")
        defer { window.close() }
        v.setSelectedRange(NSRange(location: 3, length: 0))
        let item = NSMenuItem()
        item.tag = 0
        v.heading(item)
        try await Task.sleep(for: .milliseconds(150))
        #expect(v.text == "#tag line")
    }

    func untitled(_ typed: String) async throws -> [String] {
        let vault = FileManager.default.temporaryDirectory.appending(path: "quill-title-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try "# Other\n".write(to: vault.appending(path: "Other.md"), atomically: true, encoding: .utf8)
        let ws = Workspace(vault: vault)
        let (v, window) = try await openPage("")
        defer { window.close() }
        ws.editor = v
        ws.refresh()
        ws.create()
        try await until { v.text == "# \n" }
        try await type(v, typed, at: 2)
        ws.edited()
        ws.open(vault.appending(path: "Other.md"))
        return try FileManager.default.contentsOfDirectory(atPath: vault.path).sorted()
    }

    @Test func untitledNoteTakesItsHeadingWhenLeft() async throws {
        #expect(try await untitled("Spring launch plan") == ["Other.md", "Spring launch plan.md"])
    }

    @Test func untitledTitleDropsMarkupAndLeadingDots() async throws {
        #expect(try await untitled(".**Plan**: v2") == ["Other.md", "Plan- v2.md"])
    }
}
