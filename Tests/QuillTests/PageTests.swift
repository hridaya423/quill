import AppKit
import QuillCore
import Testing
@testable import Quill

@MainActor
struct PageTests {
    static let sample = """
    ## How was my day?

    Okay. The hackathon ran long, but we placed **second** and the *pasta* was good.

    ## All I did

    - launched [Strobe](https://strobe.app)
    - ran the agent on riff, the perry ad, and printlight
      - the ad still needs a voiceover

    ## Tomorrow

    - [ ] call Sam about the cut
    - [x] send the draft

    > We build a tool that helps people write better.

    ```swift
    let quill = Page()
    ```

    See [[Voice]] for the rules.

    1. first
    2. second
    """

    func page(_ text: String = sample, dark: Bool = false, face: String = "sans") async throws -> (Page, NSWindow) {
        try await openPage(text, dark: dark, face: face)
    }

    func js(_ page: Page, _ script: String) async throws -> Any? {
        try await page.evaluateJavaScript(script)
    }

    func agent(_ page: Page, _ phrase: String, _ replacement: String, turn: Int = 1) async throws {
        let r = page.buffer.range(of: phrase)
        page.play([Change(range: r, text: replacement)], as: .agent(turn: turn, flags: []), turn: turn)
        try await until { !page.isPlaying }
        try await Task.sleep(for: .milliseconds(50))
    }

    @Test func typingInThePageKeepsTheNativeMirrorInStep() async throws {
        let (page, window) = try await page()
        defer { window.close() }
        _ = try await js(page, "quill.view.dispatch({changes: {from: 3, insert: 'So, '}, selection: {anchor: 7}})")
        _ = try await js(page, "quill.view.dispatch({changes: {from: quill.view.state.doc.length - 6, to: quill.view.state.doc.length, insert: 'last'}})")
        try await Task.sleep(for: .milliseconds(80))
        #expect(try await js(page, "quill.text()") as? String == page.text)
        #expect(page.text.hasPrefix("## So, How was my day?"))
        #expect(page.selectedRange().location == 7)
    }

    @Test func anAgentEditPlaysInAndUndoesAsOneTurn() async throws {
        let (page, window) = try await page()
        defer { window.close() }
        var resolved: [(Int, Outcome)] = []
        page.onResolve = { hunks, outcome in resolved += hunks.map { ($0.id, outcome) } }
        try await agent(page, "ran long", "ran late")
        try await agent(page, "was good", "was great")
        #expect(page.text.contains("ran late") && page.text.contains("was great"))
        #expect(page.review.hunks.count == 2)
        #expect(try await js(page, "quill.text()") as? String == page.text)
        page.undo(nil)
        try await until { page.review.isEmpty }
        #expect(page.text == Self.sample)
        #expect(resolved.filter { $0.1 == .undone }.count == 2)
        page.redo(nil)
        try await until { page.review.hunks.count == 2 }
        #expect(page.text.contains("ran late") && page.text.contains("was great"))
    }

    @Test func keepAndRevertResolveHunksAndUndoBringsThemBack() async throws {
        let (page, window) = try await page()
        defer { window.close() }
        try await agent(page, "ran long", "ran late")
        try await agent(page, "was good", "was great", turn: 2)
        let word = page.buffer.range(of: "late")
        let late = try #require(page.review.hunks.first { NSIntersectionRange($0.range, word).length > 0 })
        page.keep([late])
        #expect(page.review.hunks.count == 1)
        let great = try #require(page.review.hunks.first)
        page.revert([great])
        try await until { page.text.contains("was good") }
        #expect(page.review.isEmpty)
        #expect(page.text.contains("ran late"))
        page.undo(nil)
        try await until { page.text.contains("was great") }
        #expect(page.review.hunks.count == 1)
        page.undo(nil)
        try await until { page.review.hunks.count == 2 }
        #expect(try await js(page, "quill.text()") as? String == page.text)
    }

    @Test func typingInsideAHunkMarksItTouchedAndAcrossItResolvesIt() async throws {
        let (page, window) = try await page()
        defer { window.close() }
        var rewritten = 0
        page.onResolve = { hunks, outcome in if outcome == .rewritten { rewritten += hunks.count } }
        try await agent(page, "ran long", "ran late")
        let hunk = try #require(page.review.hunks.first)
        try await type(page, "x", at: hunk.range.location + 1)
        #expect(page.review.hunks.first?.touched == true)
        let span = NSRange(location: hunk.range.location - 2, length: hunk.range.length + 4)
        _ = try await js(page, "quill.view.dispatch({changes: {from: \(span.location), to: \(NSMaxRange(span)), insert: 'Q'}, userEvent: 'input.type'})")
        try await until { page.review.isEmpty }
        #expect(rewritten == 1)
        #expect(try await js(page, "quill.text()") as? String == page.text)
    }

    @Test func swiftEditsMapThroughTypingStillInFlight() async throws {
        let (page, window) = try await page("alpha beta gamma")
        defer { window.close() }
        let base = page.version
        _ = try await js(page, "quill.view.dispatch({changes: {from: 0, insert: 'X '}}); quill.apply([[6, 10, 'BETA']], \(base), null)")
        try await until { page.text.contains("BETA") }
        #expect(page.text == "X alpha BETA gamma")
        #expect(try await js(page, "quill.text()") as? String == page.text)
    }

    @Test func typingCostsLessThanAFrame() async throws {
        let (page, window) = try await page()
        defer { window.close() }
        let result = try await js(page, "JSON.stringify(quill.bench(300))") as? String
        print("[page bench] \(result ?? "nil")")
        let times = try JSONDecoder().decode([String: Double].self, from: try #require(result?.data(using: .utf8)))
        #expect(times["p50"]! < 8)
    }

    @Test(.enabled(if: Snapshots.dir != nil))
    func rendersReviewNotesAndPresence() async throws {
        for face in ["sans", "serif"] {
            for dark in [false, true] {
                let (page, window) = try await page(dark: dark, face: face)
                try await agent(page, "ran long, but we placed", "ran past midnight, yet we placed")
                let hunk = try #require(page.review.hunks.first)
                page.focused = hunk.id
                page.card(hunk)
                let margin = notes(from: #"[{"quote": "We build a tool", "lens": "Clarity", "note": "Lead with who it is for."}]"#, in: page.text) ?? []
                page.notes(margin, active: nil, busy: false)
                page.present(page.paragraph(at: page.buffer.range(of: "launched").location))
                try await Task.sleep(for: .milliseconds(700))
                try await still(page)
                try await Task.sleep(for: .milliseconds(300))
                let image = try await page.takeSnapshot(configuration: nil)
                let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
                let url = URL(fileURLWithPath: Snapshots.dir!).appending(path: "page-\(face)-\(dark ? "dark" : "light").png")
                try rep.representation(using: .png, properties: [:])!.write(to: url)
                window.close()
            }
        }
    }
}
