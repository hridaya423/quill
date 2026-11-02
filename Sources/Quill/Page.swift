import AppKit
import WebKit

@MainActor
final class Page: WKWebView {
    private(set) var buffer = NSMutableString()
    private(set) var selectedRange = NSRange()
    private(set) var ready = false
    private var queued: [String] = []
    var onEdit: (() -> Void)?
    var onCaret: (() -> Void)?
    var onReady: (() -> Void)?

    init() {
        let config = WKWebViewConfiguration()
        config.suppressesIncrementalRendering = true
        super.init(frame: .zero, configuration: config)
        config.userContentController.add(Relay(self), name: "quill")
        setValue(false, forKey: "drawsBackground")
        if let editor = Brand.url("Editor") {
            loadFileURL(editor.appending(path: "index.html"), allowingReadAccessTo: editor.deletingLastPathComponent())
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    var text: String { buffer as String }

    func load(_ text: String, caret: Int = 0) {
        buffer = NSMutableString(string: text)
        selectedRange = NSRange(location: caret, length: 0)
        call("quill.load(\(json(text)), \(caret))")
    }

    func replace(_ range: NSRange, with text: String) {
        buffer.replaceCharacters(in: range, with: text)
        call("quill.apply([[\(range.location), \(NSMaxRange(range)), \(json(text))]])")
    }

    func select(_ range: NSRange) {
        selectedRange = range
        call("quill.select(\(range.location), \(NSMaxRange(range)))")
    }

    func face(_ name: String) {
        call("document.documentElement.dataset.face = \(json(name))")
    }

    func evaluate(_ script: String) async throws -> Any? {
        try await evaluateJavaScript(script)
    }

    private func call(_ script: String) {
        guard ready else { return queued.append(script) }
        evaluateJavaScript(script, completionHandler: nil)
    }

    private func json(_ s: String) -> String {
        String(data: try! JSONEncoder().encode(s), encoding: .utf8)!
    }

    fileprivate func receive(_ body: [String: Any]) {
        switch body["type"] as? String {
        case "ready":
            ready = true
            for script in queued { evaluateJavaScript(script, completionHandler: nil) }
            queued = []
            onReady?()
        case "change":
            for change in (body["changes"] as? [[Any]] ?? []).reversed() {
                guard let from = change[0] as? Int, let to = change[1] as? Int, let insert = change[2] as? String else { continue }
                buffer.replaceCharacters(in: NSRange(location: from, length: to - from), with: insert)
            }
            caret(body)
            onEdit?()
        case "select":
            caret(body)
        default:
            break
        }
    }

    private func caret(_ body: [String: Any]) {
        guard let anchor = body["anchor"] as? Int, let head = body["head"] as? Int else { return }
        selectedRange = NSRange(location: min(anchor, head), length: abs(head - anchor))
        onCaret?()
    }
}

private final class Relay: NSObject, WKScriptMessageHandler {
    weak var page: Page?

    init(_ page: Page) { self.page = page }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        MainActor.assumeIsolated { page?.receive(body) }
    }
}
