import AppKit
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

    See [[Voice]] for the rules. 1. ordered items work too.

    1. first
    2. second
    """

    func page(_ dark: Bool, face: String = "serif") async throws -> (Page, NSWindow) {
        let page = Page()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 1100), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = page
        var waited = 0
        while !page.ready, waited < 200 {
            try await Task.sleep(for: .milliseconds(25))
            waited += 1
        }
        #expect(page.ready)
        page.face(face)
        page.load(Self.sample, caret: 0)
        try await Task.sleep(for: .milliseconds(300))
        return (page, window)
    }

    @Test func typingInThePageKeepsTheNativeMirrorInStep() async throws {
        let (page, window) = try await page(false)
        defer { window.close() }
        _ = try await page.evaluate("quill.view.dispatch({changes: {from: 3, insert: 'So, '}, selection: {anchor: 7}})")
        _ = try await page.evaluate("quill.view.dispatch({changes: {from: quill.view.state.doc.length - 6, to: quill.view.state.doc.length, insert: 'last'}})")
        try await Task.sleep(for: .milliseconds(100))
        let js = try await page.evaluate("quill.text()") as? String
        #expect(js == page.text)
        #expect(page.text.hasPrefix("## So, How was my day?"))
        page.replace(NSRange(location: 0, length: 2), with: "#")
        let after = try await page.evaluate("quill.text()") as? String
        #expect(after == page.text)
    }

    @Test(.enabled(if: Snapshots.dir != nil))
    func rendersMarkdownLikeAWritingApp() async throws {
        for face in ["serif", "sans"] {
            for dark in [false, true] {
                let (page, window) = try await page(dark, face: face)
                page.select(NSRange(location: (page.text as NSString).range(of: "We build").location, length: 0))
                try await Task.sleep(for: .milliseconds(200))
                let image = try await page.takeSnapshot(configuration: nil)
                let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
                let url = URL(fileURLWithPath: Snapshots.dir!).appending(path: "page-\(face)-\(dark ? "dark" : "light").png")
                try rep.representation(using: .png, properties: [:])!.write(to: url)
                window.close()
            }
        }
    }

    @Test func typingCostsLessThanAFrame() async throws {
        let (page, window) = try await page(false)
        defer { window.close() }
        let result = try await page.evaluate("JSON.stringify(quill.bench(300))") as? String
        print("[page bench] \(result ?? "nil")")
        let data = try #require(result?.data(using: .utf8))
        let times = try JSONDecoder().decode([String: Double].self, from: data)
        #expect(times["p50"]! < 8)
    }
}
