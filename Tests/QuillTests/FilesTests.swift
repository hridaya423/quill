import Foundation
import Testing
import WebKit
@testable import Quill

@MainActor
struct FilesTests {
    let home = NSHomeDirectory()

    @Test func aRootNeverExposesHiddenFilesOrLibrary() {
        let saved = Files.roots
        defer { Files.roots = saved }
        Files.roots = [home, "\(home)/honey/app"]
        #expect(!Files.allowed("\(home)/.ssh/id_ed25519"))
        #expect(!Files.allowed("\(home)/honey/app/.env"))
        #expect(!Files.allowed("\(home)/Library/Keychains/login.keychain-db"))
        #expect(Files.allowed("\(home)/honey/app/docs/shot.png"))
        #expect(!Files.allowed("/etc/hosts"))
    }

    @Test func aRootInsideAHiddenFolderStillServesItsFiles() {
        let saved = Files.roots
        defer { Files.roots = saved }
        Files.roots = ["\(home)/.t3/projects/planner"]
        #expect(Files.allowed("\(home)/.t3/projects/planner/docs/a.png"))
        #expect(!Files.allowed("\(home)/.t3/other/a.png"))
    }

    @Test func aLoneFileInABroadFolderOpensInTheHomeWindow() throws {
        #expect(AppDelegate.root(for: URL(fileURLWithPath: "\(home)/todo.md")) == nil)
        #expect(AppDelegate.root(for: URL(fileURLWithPath: "\(home)/Documents/todo.md")) == nil)
        #expect(AppDelegate.root(for: URL(fileURLWithPath: "/tmp/todo.md")) == nil)
        let project = FileManager.default.temporaryDirectory.appending(path: "quill-root-\(UUID().uuidString)")
        let nested = URL(fileURLWithPath: "\(home)/Documents/quill-root-test-\(UUID().uuidString)/notes")
        defer { try? FileManager.default.removeItem(at: nested.deletingLastPathComponent()); try? FileManager.default.removeItem(at: project) }
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        #expect(AppDelegate.root(for: nested.appending(path: "plan.md"))?.path == nested.standardizedFileURL.path)
        try FileManager.default.createDirectory(at: nested.deletingLastPathComponent().appending(path: ".git"), withIntermediateDirectories: true)
        #expect(AppDelegate.root(for: nested.appending(path: "plan.md"))?.path == nested.deletingLastPathComponent().standardizedFileURL.path)
    }

    @Test func aNoteEmbedOutsideTheAllowedTreeStaysMissing() throws {
        let saved = Files.roots
        defer { Files.roots = saved }
        let root = FileManager.default.temporaryDirectory.appending(path: "quill-embed-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appending(path: ".private"), withIntermediateDirectories: true)
        try "secret".write(to: root.appending(path: ".private/keys.md"), atomically: true, encoding: .utf8)
        try "fine".write(to: root.appending(path: "open.md"), atomically: true, encoding: .utf8)
        Files.roots = [root.path]
        let note = root.appending(path: "here.md")
        #expect(Embeds.payload(".private/keys", from: note, root: root, notes: [])["kind"] as? String == "missing")
        #expect(Embeds.payload("open", from: note, root: root, notes: [])["kind"] as? String == "note")
    }

    @Test func theEditorPageCannotBeNavigatedAway() async throws {
        let (page, window) = try await openPage("# Links\n\nAfter.\n")
        defer { window.close() }
        _ = try? await page.evaluateJavaScript("location.href = 'editor.js'; true")
        try await Task.sleep(for: .milliseconds(600))
        #expect(page.url?.isFileURL == true)
        #expect(try await page.evaluateJavaScript("typeof quill") as? String == "object")
    }

    @Test func clickingAnHTMLLinkPostsItOnceAndStays() async throws {
        let (page, window) = try await openPage("# Links\n\n<p><a href=\"https://quill.invalid/\">out</a></p>\n\nAfter.\n")
        defer { window.close() }
        let result = try await page.evaluateJavaScript("""
            (() => {
              const posted = [];
              const relay = window.webkit.messageHandlers.quill;
              const send = relay.postMessage.bind(relay);
              relay.postMessage = (m) => { if (m.type === 'link') posted.push(m.url); else send(m); };
              const a = document.querySelector('.cm-html a');
              const r = a.getBoundingClientRect();
              const down = new MouseEvent('mousedown', { bubbles: true, cancelable: true, clientX: r.left + 2, clientY: r.top + 2, button: 0, detail: 1 });
              a.dispatchEvent(down);
              return JSON.stringify({ posted, prevented: down.defaultPrevented });
            })()
            """) as? String
        #expect(result == "{\"posted\":[\"https://quill.invalid/\"],\"prevented\":true}", "\(result ?? "")")
        #expect(page.url?.isFileURL == true)
    }

    @Test func theNameIndexDropsOnlyWhenFilesComeAndGo() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "quill-index-\(UUID().uuidString)").standardizedFileURL
        defer { try? FileManager.default.removeItem(at: root) }
        let fm = FileManager.default
        try fm.createDirectory(at: root.appending(path: "a/b"), withIntermediateDirectories: true)
        try Data().write(to: root.appending(path: "a/b/one.png"))
        Embeds.warm(root)
        try await until { Embeds.locate("one.png", from: nil, root: root) != nil }
        try Data([1]).write(to: root.appending(path: "a/b/one.png"), options: .atomic)
        try Data().write(to: root.appending(path: "a/b/.hidden.tmp"))
        try Data().write(to: root.appending(path: "a/b/two.png"))
        Embeds.noticed([root.appending(path: "a/b/one.png").path, root.appending(path: "a/b/.hidden.tmp").path], root: root)
        #expect(Embeds.locate("two.png", from: nil, root: root) == nil)
        Embeds.noticed([root.appending(path: "a/b/two.png").path], root: root)
        #expect(Embeds.locate("two.png", from: nil, root: root)?.lastPathComponent == "two.png")
        try fm.removeItem(at: root.appending(path: "a/b/one.png"))
        Embeds.noticed([root.appending(path: "a/b/one.png").path], root: root)
        #expect(Embeds.locate("one.png", from: nil, root: root) == nil)
    }

    @Test func aByteRangeReadsOnlyAChunkOfABigFile() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "quill-range-\(UUID().uuidString)").resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appending(path: "clip.mp4")
        try Data(count: 10 << 20).write(to: file)
        let saved = Files.roots
        defer { Files.roots = saved }
        Files.roots.insert(root.path)
        let get = { (range: String) in
            var request = URLRequest(url: URL(string: Files.url(file))!)
            request.setValue(range, forHTTPHeaderField: "Range")
            let task = SchemeTask(request)
            Files().webView(WKWebView(), start: task)
            return "\(task.status) \(task.headers["Content-Range"] ?? "") \(task.body.count)"
        }
        #expect(get("bytes=1048576-") == "206 bytes 1048576-9437183/10485760 8388608")
        #expect(get("bytes=0-99") == "206 bytes 0-99/10485760 100")
    }

    @Test func aFolderWindowListsItsNotesOffTheMainThread() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "quill-scan-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appending(path: "deep"), withIntermediateDirectories: true)
        try "# Older\n".write(to: root.appending(path: "Older.md"), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date.distantPast], ofItemAtPath: root.appending(path: "Older.md").path)
        try "# Newest\n".write(to: root.appending(path: "deep/Newest.md"), atomically: true, encoding: .utf8)
        let ws = Workspace(vault: root, home: false)
        ws.replace(ScriptedAgent([]))
        defer { ws.quit() }
        ws.start()
        #expect(ws.notes.isEmpty)
        try await until { ws.current?.lastPathComponent == "Newest.md" }
        #expect(ws.notes.map(\.title) == ["Newest", "Older"])
    }
}

final class SchemeTask: NSObject, WKURLSchemeTask {
    let request: URLRequest
    var status = 0
    var headers: [String: String] = [:]
    var body = Data()
    init(_ request: URLRequest) { self.request = request }
    func didReceive(_ response: URLResponse) {
        let http = response as! HTTPURLResponse
        status = http.statusCode
        headers = http.allHeaderFields as? [String: String] ?? [:]
    }
    func didReceive(_ data: Data) { body.append(data) }
    func didFinish() {}
    func didFailWithError(_ error: any Error) { status = -1 }
}
